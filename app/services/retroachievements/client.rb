# frozen_string_literal: true

require "faraday"
require "json"

module Retroachievements
  # Per-member client over the RetroAchievements Web API, ported from
  # xergasa's single-user client. Members are addressed by their RA ULID (the
  # Linked Account's external_id), never by username: usernames can change.
  # Only #user_profile accepts a username, to resolve it to the ULID.
  #
  # Results are normalised into the shared Achievements::Providers value
  # objects. 404 / unknown users raise Achievements::Providers::NotFound and a
  # 429 that outlasts the short in-client retry raises RateLimited; any other
  # failure raises Retroachievements::Client::Error.
  class Client
    class ConfigurationError < Achievements::Providers::ConfigurationError; end
    class Error < StandardError; end

    API_BASE_URL = "https://retroachievements.org"
    MEDIA_BASE_URL = "https://media.retroachievements.org"
    USER_AGENT = "RPGClubApi/AchievementHub"

    OPEN_TIMEOUT_SECONDS = 5
    TIMEOUT_SECONDS = 15
    MAX_ATTEMPTS = 3
    BASE_BACKOFF_SECONDS = 0.5
    MAX_BACKOFF_SECONDS = 5.0
    TRANSIENT_STATUSES = [ 307, 408, 425, 429 ].freeze
    COMPLETION_PAGE_SIZE = 500 # GetUserCompletionProgress's max `c`
    RECENTLY_PLAYED_PAGE_SIZE = 50 # GetUserRecentlyPlayedGames's max `c`

    # `http` and `sleeper` are seams for specs: a Faraday connection and a
    # callable taking seconds to wait.
    def initialize(api_key: nil, http: nil, sleeper: nil)
      @api_key = api_key
      @http = http
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
    end

    # Resolves a username or ULID to { external_id: ULID, display_name:
    # current username, avatar_url: }. Untracked (banned) users can't be linked.
    def user_profile(username_or_ulid)
      data = get("API_GetUserProfile.php", u: username_or_ulid)
      ulid = data.is_a?(Hash) ? data["ULID"].to_s.strip : ""
      if ulid.empty? || data["Untracked"].to_i == 1
        raise Achievements::Providers::NotFound, "RetroAchievements user #{username_or_ulid} was not found."
      end

      { external_id: ulid, display_name: data["User"], avatar_url: media_url(data["UserPic"]) }
    end

    # The member's played Achievement Sets as Achievements::Providers::PlayedSet.
    #
    # Without `since` (Backfill): GetUserCompletionProgress, 500 per page,
    # keeping sets with at least one award; activity_at is the most recent
    # award. With `since` (incremental): GetUserRecentlyPlayedGames, 50 per
    # page, newest first, stopping at the first game last played before
    # `since` (CompletionProgress carries no last-played date); games without
    # Achievements or without any Unlock are skipped, matching the Backfill.
    def played_sets(ulid, since: nil)
      since ? recently_played_sets(ulid, since) : completion_progress_sets(ulid)
    end

    # One game's Achievement Set and the member's progress, from a single
    # GetGameInfoAndUserProgress call, as an Achievements::Providers::SetDefinition.
    #
    # Rarity is the share of the game's players (NumDistinctPlayers) holding
    # the Achievement, as a percentage rounded to 2 decimals: NumAwarded for
    # `rarity`, NumAwardedHardcore for `rarity_hardcore`. Both use the same
    # denominator, which is what the RA site shows. Each Unlock keeps both
    # dates: a hardcore Unlock carries hardcore_unlocked_at, a softcore one
    # only unlocked_at. Playtime is reported in seconds and floored to minutes.
    def set_with_progress(ulid, game_id)
      data = get("API_GetGameInfoAndUserProgress.php", g: game_id, u: ulid, a: 1)
      raise Error, "RetroAchievements returned no game #{game_id}." unless data.is_a?(Hash)

      # Achievements is an object keyed by id, not an array ([] when empty).
      raw_achievements = data["Achievements"].is_a?(Hash) ? data["Achievements"].values : []
      players = data["NumDistinctPlayers"].to_i

      Achievements::Providers::SetDefinition.new(
        external_id: (data["ID"] || game_id).to_s,
        title: data["Title"],
        platform_label: data["ConsoleName"],
        icon_url: media_url(data["ImageIcon"]),
        achievements: raw_achievements.map { |raw| achievement_definition(raw, players) },
        unlocks: raw_achievements.filter_map { |raw| provider_unlock(raw) },
        playtime_minutes: data["UserTotalPlaytime"]&.then { |seconds| seconds.to_i / 60 }
      )
    end

    private

    def achievement_definition(raw, players)
      badge = raw["BadgeName"].presence
      Achievements::Providers::AchievementDefinition.new(
        external_id: raw["ID"].to_s,
        name: raw["Title"],
        description: raw["Description"],
        icon_url: badge && "#{MEDIA_BASE_URL}/Badge/#{badge}.png",
        # UNVERIFIED: RA serves a greyed `_lock.png` variant of every badge.
        icon_locked_url: badge && "#{MEDIA_BASE_URL}/Badge/#{badge}_lock.png",
        hidden: false,
        points: raw["Points"]&.to_i,
        display_order: raw["DisplayOrder"]&.to_i,
        rarity: rarity(raw["NumAwarded"], players),
        rarity_hardcore: rarity(raw["NumAwardedHardcore"], players)
      )
    end

    def provider_unlock(raw)
      hardcore_at = parse_time(raw["DateEarnedHardcore"])
      unlocked_at = parse_time(raw["DateEarned"]) || hardcore_at
      return unless unlocked_at

      Achievements::Providers::ProviderUnlock.new(
        achievement_external_id: raw["ID"].to_s, unlocked_at: unlocked_at, hardcore_unlocked_at: hardcore_at
      )
    end

    def rarity(awarded, players)
      return unless players.positive?

      [ BigDecimal(awarded.to_i) * 100 / players, BigDecimal(100) ].min.round(2)
    end

    def completion_progress_sets(ulid)
      sets = []
      offset = 0
      loop do
        data = get("API_GetUserCompletionProgress.php", u: ulid, c: COMPLETION_PAGE_SIZE, o: offset)
        page = data.is_a?(Hash) ? Array(data["Results"]) : []
        page.each do |game|
          next unless game["NumAwarded"].to_i.positive? || game["NumAwardedHardcore"].to_i.positive?

          sets << played_set(game, achievements_count: game["MaxPossible"], activity_at: game["MostRecentAwardedDate"])
        end

        offset += page.size
        break if page.size < COMPLETION_PAGE_SIZE || offset >= data["Total"].to_i
      end
      sets
    end

    def recently_played_sets(ulid, since)
      sets = []
      offset = 0
      loop do
        data = get("API_GetUserRecentlyPlayedGames.php", u: ulid, c: RECENTLY_PLAYED_PAGE_SIZE, o: offset)
        page = data.is_a?(Array) ? data : []
        page.each do |game|
          last_played = parse_time(game["LastPlayed"])
          return sets if last_played.nil? || last_played < since

          achievements_count = (game["NumPossibleAchievements"] || game["AchievementsTotal"]).to_i
          next unless achievements_count.positive?
          next unless game["NumAchieved"].to_i.positive? || game["NumAchievedHardcore"].to_i.positive?

          sets << played_set(game, achievements_count: achievements_count, activity_at: last_played)
        end

        break if page.size < RECENTLY_PLAYED_PAGE_SIZE

        offset += page.size
      end
      sets
    end

    def played_set(game, achievements_count:, activity_at:)
      Achievements::Providers::PlayedSet.new(
        external_id: game["GameID"].to_s,
        title: game["Title"],
        platform_label: game["ConsoleName"],
        icon_url: media_url(game["ImageIcon"]),
        achievements_count: achievements_count.to_i,
        activity_at: activity_at.is_a?(String) ? parse_time(activity_at) : activity_at
      )
    end

    # RA returns plain "YYYY-MM-DD HH:MM:SS" UTC strings.
    def parse_time(value)
      return if value.blank?

      Time.find_zone!("UTC").parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def media_url(path)
      return if path.blank?

      "#{MEDIA_BASE_URL}#{path.start_with?("/") ? path : "/#{path}"}"
    end

    # GET an RA Web API endpoint. 404 is NotFound. 429, 5xx and other
    # transient statuses (and network / JSON failures) are retried briefly
    # with backoff honouring Retry-After; long back-off is the sync engine's job.
    def get(endpoint, params)
      query = params.merge(y: api_key)
      last_failure = nil

      1.upto(MAX_ATTEMPTS) do |attempt|
        begin
          response = http.get("/API/#{endpoint}", query)
          return JSON.parse(response.body) if response.success?

          wait = handle_http_failure!(response, endpoint, attempt)
        rescue Faraday::Error, JSON::ParserError => error
          last_failure = error
          raise Error, "RetroAchievements #{endpoint} failed: #{error.message}" if attempt >= MAX_ATTEMPTS

          wait = backoff(attempt)
        end

        @sleeper.call(wait)
      end

      raise Error, "RetroAchievements #{endpoint} failed: #{last_failure&.message}"
    end

    # Raises for a response that must not (or can no longer) be retried;
    # otherwise returns how long to wait before the next attempt.
    def handle_http_failure!(response, endpoint, attempt)
      status = response.status
      raise Achievements::Providers::NotFound, "RetroAchievements #{endpoint} returned 404." if status == 404

      if status == 429
        retry_after = retry_after(response)
        if attempt >= MAX_ATTEMPTS || retry_after.to_f > MAX_BACKOFF_SECONDS
          raise Achievements::Providers::RateLimited.new(
            "RetroAchievements is rate limiting requests.", retry_after: retry_after
          )
        end
        return retry_after || backoff(attempt)
      end

      transient = TRANSIENT_STATUSES.include?(status) || status >= 500
      raise Error, "RetroAchievements #{endpoint} returned HTTP #{status}." if !transient || attempt >= MAX_ATTEMPTS

      retry_after(response) || backoff(attempt)
    end

    def retry_after(response)
      seconds = Float(response.headers["Retry-After"], exception: false)
      seconds if seconds && seconds >= 0
    end

    def backoff(attempt)
      [ MAX_BACKOFF_SECONDS, BASE_BACKOFF_SECONDS * (2**(attempt - 1)) ].min
    end

    def http
      @http ||= Faraday.new(url: API_BASE_URL, headers: { "User-Agent" => USER_AGENT }) do |connection|
        connection.options.open_timeout = OPEN_TIMEOUT_SECONDS
        connection.options.timeout = TIMEOUT_SECONDS
      end
    end

    def api_key
      @api_key ||= ENV["RETROACHIEVEMENTS_API_KEY"].to_s.strip.presence
      return @api_key if @api_key.present? && @api_key != "change_me"

      raise ConfigurationError, "RETROACHIEVEMENTS_API_KEY must be set"
    end
  end
end
