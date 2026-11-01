# frozen_string_literal: true

require "faraday"
require "json"

module Steam
  # Port of the Discord bot's SteamApiService (b/services/SteamApiService.ts):
  # resolves a Steam profile identifier to a SteamID64 and fetches the owned
  # games plus the persona name. Error codes and the retry/backoff policy match
  # the bot so both clients report the same failures.
  class Client
    class ConfigurationError < Achievements::Providers::ConfigurationError; end

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
    PLATFORM_LABEL = "PC"
    APP_ICON_URL = "https://media.steampowered.com/steamcommunity/public/images/apps/%<app_id>s/%<hash>s.jpg"

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

    # Achievement Hub: the member's played games as
    # Achievements::Providers::PlayedSet, one per appid with playtime. With
    # `since`, only games last played after it (rtime_last_played is the delta
    # signal). Skips the persona-name lookup owned_games makes. Raises
    # Achievements::Providers::Private when Steam hides the game details.
    def played_sets(steam_id64, since: nil)
      ensure_steam_id64!(steam_id64)

      response = provider_errors do
        request_json(
          "/IPlayerService/GetOwnedGames/v1/",
          steamid: steam_id64, include_appinfo: "1", include_played_free_games: "1"
        )["response"] || {}
      end
      # A profile with private game details answers with an empty response;
      # a public, empty library still reports its game_count.
      raise Achievements::Providers::Private, "Steam game details are private." unless response.key?("games") ||
        response.key?("game_count")

      Array(response["games"]).filter_map { |raw_game| played_set(raw_game, since) }
    end

    # Achievement Hub: one game's Achievement Set merged from GetSchemaForGame
    # (definitions), GetPlayerAchievements (the member's Unlocks) and
    # GetGlobalAchievementPercentagesForApp (Rarity), as an
    # Achievements::Providers::SetDefinition. nil when the game has no
    # Achievement Set (empty schema) or Steam has no stats for the member on it.
    # A non-public profile raises Achievements::Providers::Private, never zero
    # Unlocks. Steam reports no playtime here: it rides on the PlayedSet.
    def set_with_progress(steam_id64, app_id)
      ensure_steam_id64!(steam_id64)

      provider_errors do
        game = request_json("/ISteamUserStats/GetSchemaForGame/v2/", appid: app_id.to_s, l: "english")["game"] || {}
        raw_achievements = Array(game.dig("availableGameStats", "achievements"))
        next if raw_achievements.empty?

        stats = player_stats(steam_id64, app_id)
        next unless stats

        rarities = global_rarities(app_id)
        Achievements::Providers::SetDefinition.new(
          external_id: app_id.to_s,
          title: stats["gameName"].to_s.strip.presence || game["gameName"].to_s.strip,
          platform_label: PLATFORM_LABEL,
          achievements: raw_achievements.each_with_index.map do |raw, index|
            achievement_definition(raw, index + 1, rarities[raw["name"]])
          end,
          unlocks: Array(stats["achievements"]).filter_map { |entry| provider_unlock(entry) }
        )
      end
    end

    private

    # The member's playerstats for one app, or nil when Steam has no stats for
    # them there (an unowned app or one without stats answers 400 or
    # success: false). A non-public profile raises private_profile.
    def player_stats(steam_id64, app_id)
      payload = request_json_tolerating(
        "/ISteamUserStats/GetPlayerAchievements/v1/", { steamid: steam_id64, appid: app_id.to_s, l: "english" }, [ 400 ]
      )
      stats = payload["playerstats"]
      return stats if stats.is_a?(Hash) && stats["success"]

      if stats.is_a?(Hash) && stats["error"].to_s.match?(/not public/i)
        raise Error.new("private_profile", "Steam profile appears private. Set games/profile visibility to public.")
      end

      nil
    end

    # apiname => Rarity (BigDecimal, two places). Steam has served `percent` as
    # both a number and a string, so both parse.
    def global_rarities(app_id)
      payload = request_json("/ISteamUserStats/GetGlobalAchievementPercentagesForApp/v2/", gameid: app_id.to_s)
      Array(payload.dig("achievementpercentages", "achievements")).each_with_object({}) do |entry, rarities|
        percent = BigDecimal(entry["percent"].to_s, exception: false)
        rarities[entry["name"]] = percent.round(2) if percent
      end
    end

    # Hidden achievements come without a description; it stays nil.
    def achievement_definition(raw, display_order, rarity)
      Achievements::Providers::AchievementDefinition.new(
        external_id: raw["name"],
        name: raw["displayName"].to_s.strip,
        description: raw["description"].to_s.strip.presence,
        icon_url: raw["icon"].presence,
        icon_locked_url: raw["icongray"].presence,
        hidden: raw["hidden"].to_i == 1,
        display_order: display_order,
        rarity: rarity
      )
    end

    def provider_unlock(entry)
      return unless entry["achieved"].to_i == 1

      unlock_time = entry["unlocktime"].to_i
      Achievements::Providers::ProviderUnlock.new(
        achievement_external_id: entry["apiname"],
        unlocked_at: unlock_time.positive? ? Time.at(unlock_time).utc : nil
      )
    end

    # Maps this client's privacy and rate-limit failures onto the shared
    # Provider errors the sync units understand; other failures pass through.
    def provider_errors
      yield
    rescue Error => error
      case error.code
      when "private_profile" then raise Achievements::Providers::Private, error.message
      when "api_rate_limited" then raise Achievements::Providers::RateLimited, error.message
      else raise
      end
    end

    def played_set(raw_game, since)
      game = owned_game(raw_game)
      return if game.nil? || game[:playtime_forever_minutes] <= 0
      return if since && (game[:last_played_at].nil? || game[:last_played_at] <= since)

      icon_hash = raw_game["img_icon_url"].to_s.strip
      Achievements::Providers::PlayedSet.new(
        external_id: game[:app_id].to_s,
        title: game[:name],
        platform_label: PLATFORM_LABEL,
        icon_url: icon_hash.empty? ? nil : format(APP_ICON_URL, app_id: game[:app_id], hash: icon_hash),
        activity_at: game[:last_played_at],
        playtime_minutes: game[:playtime_forever_minutes]
      )
    end

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
      request_json_tolerating(path, params, [])
    end

    # request_json, except that the HTTP statuses in `tolerated` return their
    # JSON body instead of failing.
    def request_json_tolerating(path, params, tolerated)
      query = params.merge(key: api_key)
      last_failure = nil

      1.upto(MAX_ATTEMPTS) do |attempt|
        wait_for_rate_limit

        begin
          response = http.get(path, query)
          return JSON.parse(response.body) if response.success? || tolerated.include?(response.status)

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
