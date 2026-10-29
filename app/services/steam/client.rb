# frozen_string_literal: true

require "faraday"
require "json"

module Steam
  # Port of the Discord bot's SteamApiService (b/services/SteamApiService.ts):
  # resolves a Steam profile identifier to a SteamID64 and fetches the owned
  # games plus the persona name. Error codes and the retry/backoff policy match
  # the bot so both clients report the same failures.
  class Client
    class ConfigurationError < StandardError; end

    class Error < StandardError
      CODES = %w[
        invalid_identifier private_profile api_unavailable api_rate_limited api_unauthorized
      ].freeze

      attr_reader :code

      def initialize(code, message)
        raise ArgumentError, "unknown Steam error code #{code.inspect}" unless CODES.include?(code)

        @code = code
        super(message)
      end
    end

    API_BASE_URL = "https://api.steampowered.com"

    STEAM_ID64_REGEX = /\A\d{17}\z/
    PROFILE_URL_REGEX = %r{\Ahttps?://steamcommunity\.com/(id|profiles)/([^/?#]+)}i
    VANITY_REGEX = /\A[a-zA-Z0-9_-]{2,64}\z/

    TIMEOUT_SECONDS = 15
    MAX_ATTEMPTS = 4
    MIN_INTERVAL_SECONDS = 0.25
    MAX_BACKOFF_SECONDS = 5.0
    BASE_BACKOFF_SECONDS = 0.5
    MAX_JITTER_SECONDS = 0.25
    USER_AGENT = "RPGClubApi/SteamImport"

    # `http`, `sleeper` and `clock` are seams for specs: a Faraday connection, a
    # callable taking seconds to wait, and a callable returning monotonic
    # seconds.
    def initialize(api_key: nil, http: nil, sleeper: nil, clock: nil)
      @api_key = api_key
      @http = http
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @next_allowed_at = nil
    end

    # Resolve a SteamID64, a steamcommunity.com profiles/ or id/ URL, or a bare
    # vanity name. Returns { steam_id64:, identifier_kind:, raw_identifier:,
    # profile_path: }. identifier_kind is one of steamid64, profiles_url,
    # vanity_url, vanity.
    def resolve_profile(raw_identifier)
      kind, value = parse_identifier(raw_identifier)
      steam_id64 = if %w[steamid64 profiles_url].include?(kind)
        value
      else
        request_json("/ISteamUser/ResolveVanityURL/v1/", vanityurl: value).dig("response", "steamid").to_s.strip
      end

      unless steam_id64&.match?(STEAM_ID64_REGEX)
        raise Error.new("invalid_identifier", "Steam profile id is not a valid SteamID64.")
      end

      {
        steam_id64: steam_id64,
        identifier_kind: kind,
        raw_identifier: raw_identifier,
        profile_path: "profiles/#{steam_id64}"
      }
    end

    # { profile_name: } from GetPlayerSummaries; the name is nil when Steam
    # lists no player for the id.
    def player_summary(steam_id64)
      ensure_steam_id64!(steam_id64)

      payload = request_json("/ISteamUser/GetPlayerSummaries/v2/", steamids: steam_id64)
      { profile_name: payload.dig("response", "players", 0, "personaname")&.strip }
    end

    # The owned library: { steam_id64:, profile_name:, game_count:, games: [...] }.
    # Each game is { app_id:, name:, playtime_forever_minutes:,
    # playtime_{windows,mac,linux,deck}_minutes: (nil when Steam omits them),
    # last_played_at: (Time or nil) }. Entries without an appid or name are
    # dropped. An empty library raises private_profile, as Steam hides the games
    # of a profile whose game details are private.
    def owned_games(steam_id64)
      ensure_steam_id64!(steam_id64)

      payload = request_json(
        "/IPlayerService/GetOwnedGames/v1/",
        steamid: steam_id64, include_appinfo: "1", include_played_free_games: "1"
      )
      games = Array(payload.dig("response", "games")).filter_map { |raw_game| owned_game(raw_game) }
      game_count = Integer(payload.dig("response", "game_count") || games.size)
      profile_name = player_summary(steam_id64)[:profile_name]

      if games.empty?
        raise Error.new("private_profile", "No visible games were returned. Ensure your Steam game details are public.")
      end

      { steam_id64: steam_id64, profile_name: profile_name, game_count: game_count, games: games }
    end

    private

    def ensure_steam_id64!(steam_id64)
      return if steam_id64.to_s.match?(STEAM_ID64_REGEX)

      raise Error.new("invalid_identifier", "Steam ID must be a 17-digit SteamID64.")
    end

    def owned_game(raw_game)
      app_id = raw_game["appid"].to_i
      name = raw_game["name"].to_s.strip
      return if app_id <= 0 || name.empty?

      last_played = raw_game["rtime_last_played"].to_i
      {
        app_id: app_id,
        name: name,
        playtime_forever_minutes: raw_game["playtime_forever"].to_i,
        playtime_windows_minutes: raw_game["playtime_windows_forever"]&.to_i,
        playtime_mac_minutes: raw_game["playtime_mac_forever"]&.to_i,
        playtime_linux_minutes: raw_game["playtime_linux_forever"]&.to_i,
        playtime_deck_minutes: raw_game["playtime_deck_forever"]&.to_i,
        last_played_at: last_played.positive? ? Time.at(last_played).utc : nil
      }
    end

    # GET a Steam Web API path, mirroring the bot's requestJson: requests are
    # spaced MIN_INTERVAL_SECONDS apart, 401/403 fail at once, 429 and 5xx are
    # retried with exponential backoff (or Retry-After) up to MAX_ATTEMPTS, and
    # network or JSON failures are retried the same way.
    def request_json(path, params)
      query = params.merge(key: api_key)
      last_failure = nil

      1.upto(MAX_ATTEMPTS) do |attempt|
        wait_for_rate_limit

        begin
          response = http.get(path, query)
          return JSON.parse(response.body) if response.success?

          retry_after = handle_http_failure!(response, attempt)
        rescue Faraday::Error, JSON::ParserError => error
          last_failure = error
          raise Error.new("api_unavailable", error.message) if attempt >= MAX_ATTEMPTS
        end

        @sleeper.call((retry_after || backoff(attempt)) + (rand * MAX_JITTER_SECONDS))
      end

      raise Error.new("api_unavailable", last_failure&.message || "Steam API request failed.")
    end

    # Raises for a failed response that must not (or can no longer) be retried;
    # otherwise returns the Retry-After delay in seconds (nil when absent).
    def handle_http_failure!(response, attempt)
      status = response.status
      raise Error.new("api_unauthorized", "Steam API key is invalid or unauthorized.") if status == 401
      if status == 403
        raise Error.new("private_profile", "Steam profile appears private. Set games/profile visibility to public.")
      end
      if status == 429 && attempt >= MAX_ATTEMPTS
        raise Error.new("api_rate_limited", "Steam API is rate limiting requests. Please retry shortly.")
      end

      retryable = status == 429 || status >= 500
      raise Error.new("api_unavailable", "Steam API returned HTTP #{status}.") if !retryable || attempt >= MAX_ATTEMPTS

      retry_after(response)
    end

    def retry_after(response)
      seconds = Float(response.headers["Retry-After"], exception: false)
      seconds if seconds && seconds >= 0
    end

    def backoff(attempt)
      [ MAX_BACKOFF_SECONDS, BASE_BACKOFF_SECONDS * (2**(attempt - 1)) ].min
    end

    def wait_for_rate_limit
      now = @clock.call
      @sleeper.call(@next_allowed_at - now) if @next_allowed_at && now < @next_allowed_at
      @next_allowed_at = @clock.call + MIN_INTERVAL_SECONDS
    end

    def http
      @http ||= Faraday.new(url: API_BASE_URL, headers: { "User-Agent" => USER_AGENT }) do |connection|
        connection.options.timeout = TIMEOUT_SECONDS
      end
    end

    def api_key
      @api_key ||= ENV.fetch("STEAM_WEB_API_KEY", ENV.fetch("STEAM_API_KEY", nil)).to_s.strip.presence
      return @api_key if @api_key.present? && @api_key != "change_me"

      raise ConfigurationError, "STEAM_WEB_API_KEY must be set"
    end

    def parse_identifier(raw_identifier)
      trimmed = raw_identifier.to_s.strip
      raise Error.new("invalid_identifier", "Steam profile identifier is required.") if trimmed.empty?

      return [ "steamid64", trimmed ] if trimmed.match?(STEAM_ID64_REGEX)

      if (match = PROFILE_URL_REGEX.match(trimmed))
        return [ match[1].casecmp?("profiles") ? "profiles_url" : "vanity_url", match[2] ]
      end

      return [ "vanity", trimmed ] if trimmed.match?(VANITY_REGEX)

      raise Error.new("invalid_identifier", "Unsupported Steam profile identifier format.")
    end
  end
end
