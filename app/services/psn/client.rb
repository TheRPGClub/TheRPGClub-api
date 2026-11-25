# frozen_string_literal: true

require "faraday"
require "json"

module Psn
  # Reads members' PSN trophies through the club-owned PSN account (ADR 0002).
  # Ported from xergasa's single-user Psn::Client, with `users/me` swapped for
  # the member's accountId.
  #
  # Auth: the club account's NPSSO buys an OAuth code, which is exchanged for an
  # access token (about 1h). The access and refresh tokens are cached in
  # Rails.cache; an expired access token is renewed with the refresh token when
  # one is cached, else with a fresh NPSSO exchange. When the NPSSO no longer
  # authenticates, `psn_auth_expired_at` is recorded once in the hub state (the
  # bot alerts admins) and AuthExpired is raised; the next successful auth
  # clears it.
  #
  # Every request counts against one shared budget (about 300 requests per 15
  # minutes, UNVERIFIED), because every member is read through the same
  # account. This client does not pace; the tick engine does (api-07).
  #
  # `http`, `cache`, `hub_state`, `sleeper` and `clock` are seams for specs.
  class Client
    # Unexpected Provider responses (5xx after retries, malformed bodies).
    class Error < Achievements::Providers::Error; end

    AUTHORIZE_URL = "https://ca.account.sony.com/api/authz/v3/oauth/authorize"
    TOKEN_URL = "https://ca.account.sony.com/api/authz/v3/oauth/token"
    API_BASE_URL = "https://m.np.playstation.com/api"
    SEARCH_URL = "#{API_BASE_URL}/search/v1/universalSearch"
    # The member's play history (spike api#462: readable for non-friends).
    PLAYED_URL = "#{API_BASE_URL}/gamelist/v2/users/%s/titles"
    # titleId (CUSA/PPSA) -> trophy list, at most BRIDGE_BATCH ids per call.
    TITLE_TROPHY_TITLES_URL = "#{API_BASE_URL}/trophy/v1/users/%s/titles/trophyTitles"
    # UNVERIFIED: legacy profile host, may be retired (research §4 (b)).
    PROFILE_URL = "https://us-prof.np.community.playstation.net/userProfile/v1/users/%s/profile2"
    PROFILE_FIELDS = "npId,onlineId,accountId,avatarUrls"
    AVATAR_SIZES = %w[s m l xl].freeze
    REDIRECT_URI = "com.scee.psxandroid.scecompcall://redirect"
    OAUTH_CLIENT_ID = "09515159-7237-4370-9b40-3806e67c0891"
    SCOPE = "psn:mobile.v2.core psn:clientapp"
    # Basic base64(client_id:client_secret) of Sony's official mobile app; a
    # well-known public constant, not a secret.
    CLIENT_AUTH = "Basic MDk1MTUxNTktNzIzNy00MzcwLTliNDAtMzgwNmU2N2MwODkxOnVjUGprYTV0bnRCMktxc1A="

    ACCESS_TOKEN_CACHE_KEY = "psn:access_token"
    REFRESH_TOKEN_CACHE_KEY = "psn:refresh_token"
    TOKEN_SAFETY_MARGIN = 60
    AUTH_EXPIRED_KEY = "psn_auth_expired_at"

    TITLES_PAGE = 800 # the trophy-titles endpoint's max `limit`
    PLAYED_PAGE = 200 # the gamelist endpoint's page
    # The spike's query. `unknown` titles (apps, some games) come back anyway.
    PLAYED_CATEGORIES = "ps4_game,ps5_native_game"
    BRIDGE_BATCH = 5 # the bridge 400s on more ids
    # A title's trophy list never changes, so a bridged id is kept a long
    # time. A title with none is kept per member and for less: the bridge
    # answers for the member, who may not have started its trophies yet.
    BRIDGE_CACHE_KEY = "psn:np_communication_id:%s"
    BRIDGE_MISS_CACHE_KEY = "psn:np_communication_id:none:%s:%s"
    BRIDGE_TTL = 90.days
    BRIDGE_MISS_TTL = 7.days

    # One title of a member's play history, bridged to its trophy list
    # (external_id, the npCommunicationId). PSN times each edition (PS4, PS5)
    # separately, so several titles can share one trophy list.
    PlayedGame = Data.define(:title_id, :external_id, :title, :minutes)

    # Sony's access-control error, returned for private trophies (research §4).
    # UNVERIFIED: the code and message have not been confirmed against a real
    # private account; the message match is the fallback.
    ACCESS_CONTROL_CODE = 2_240_526
    ACCESS_CONTROL_MESSAGE = /access control/i

    # xergasa's short timeouts (PlatformHttp).
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 15
    WRITE_TIMEOUT = 15
    MAX_ATTEMPTS = 3
    BASE_BACKOFF_SECONDS = 0.5
    MAX_BACKOFF_SECONDS = 5.0
    TRANSIENT_STATUSES = [ 307, 408, 425, *500..599 ].freeze
    # A server-closed keep-alive socket (the SSL_read EOF stalls xergasa hit)
    # surfaces as one of these; one retry on a fresh request is the remedy.
    STALE_CONNECTION_ERRORS = [ Faraday::SSLError, Faraday::ConnectionFailed ].freeze
    USER_AGENT = "RPGClubApi/AchievementHub"

    def initialize(npsso: nil, http: nil, cache: nil, hub_state: nil, sleeper: nil, clock: nil)
      @npsso = npsso
      @http = http
      @cache = cache || Rails.cache
      @hub_state = hub_state
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      @clock = clock || -> { Time.current }
    end

    # The member's played Achievement Sets (their trophy titles), newest first.
    # UNVERIFIED: the trophy-titles endpoint answering for another user's
    # accountId (xergasa only ever read `users/me`).
    # With `since`, stops at the first title last updated before it: the list
    # is sorted by lastUpdatedDateTime descending (research §4).
    def played_sets(account_id, since: nil)
      collected = []
      offset = 0

      loop do
        data = api_get("/trophy/v1/users/#{escape(account_id)}/trophyTitles", { limit: TITLES_PAGE, offset: offset })
        page = Array(data["trophyTitles"])
        sets = page.map { |row| played_set(row) }
        fresh = since ? sets.take_while { |set| set.activity_at.nil? || set.activity_at >= since } : sets
        collected.concat(fresh)

        offset += page.size
        break if page.empty? || fresh.size < sets.size || offset >= data["totalItemCount"].to_i
      end

      collected
    end

    # The member's play history as PlayedGames (spec api#457 "PSN Playtime").
    # Pages the gamelist and bridges each titleId to its npCommunicationId;
    # titles with no trophy list (apps, most `unknown` titles) are left out.
    # A hidden history (403, access control) or an unknown account reads as
    # none. A bridge batch that fails leaves its titles out for this read;
    # RateLimited and AuthExpired go to the tick as everywhere else.
    def played_games(account_id)
      titles = played_titles(account_id)
      np_ids = bridge(account_id, titles.map { |title| title["titleId"] })

      titles.filter_map do |title|
        external_id = np_ids[title["titleId"]]
        next unless external_id

        PlayedGame.new(title_id: title["titleId"], external_id: external_id, title: title["name"],
          minutes: duration_minutes(title["playDuration"]))
      end
    end

    # The club account's NPSSO from credentials or PSN_NPSSO, if any.
    def self.configured_npsso
      Rails.application.credentials.psn_npsso.presence || ENV["PSN_NPSSO"].presence
    end

    # Whether an NPSSO is set at all (says nothing about Sony accepting it).
    def self.npsso_configured?
      configured_npsso.present?
    end

    # Authenticates the club account (a cached token counts). Clears
    # `psn_auth_expired_at` on success; raises AuthExpired while the NPSSO is
    # still refused. The Sync Window's way out of the PSN pause.
    def authenticate!
      access_token
      true
    end

    # Online ID -> { external_id: accountId, display_name: onlineId,
    # avatar_url: }. Online IDs can be renamed, so callers store the
    # accountId. Searches first (an exact, case-insensitive onlineId match),
    # then falls back to the legacy profile endpoint, which also finds the
    # club account itself (search never returns the authenticating account).
    def resolve_account(online_id)
      online_id = online_id.to_s.strip
      raise Achievements::Providers::NotFound, "PSN online ID is required" if online_id.empty?

      search_account(online_id) || profile_account(online_id) ||
        raise(Achievements::Providers::NotFound, "No PSN account with online ID #{online_id}")
    end

    # The set's definitions merged with the member's Unlocks. Rarity
    # (trophyEarnedRate) only comes from the per-member endpoint (research §4);
    # when the member has never synced the title, Sony answers 404 there and
    # the set counts as nothing earned (and carries no Rarity).
    def set_with_progress(account_id, np_communication_id, np_service_name)
      params = { npServiceName: np_service_name }
      definitions = api_get("/trophy/v1/npCommunicationIds/#{escape(np_communication_id)}/trophyGroups/all/trophies", params)
      earned = member_trophies(account_id, np_communication_id, params)

      Achievements::Providers::SetDefinition.new(
        external_id: np_communication_id,
        title: nil, # the definitions endpoint has no title; it comes from the PlayedSet
        np_service_name: np_service_name,
        achievements: Array(definitions["trophies"]).map { |trophy| achievement(trophy, earned[trophy["trophyId"].to_s]) },
        unlocks: earned.values.select { |trophy| trophy["earned"] == true }.map { |trophy| unlock(trophy) }
      )
    end

    private

    # trophyId (string) -> the member's trophy row.
    def member_trophies(account_id, np_communication_id, params)
      data = api_get(
        "/trophy/v1/users/#{escape(account_id)}/npCommunicationIds/#{escape(np_communication_id)}/trophyGroups/all/trophies",
        params
      )
      Array(data["trophies"]).index_by { |trophy| trophy["trophyId"].to_s }
    rescue Achievements::Providers::NotFound
      {}
    end

    def achievement(trophy, earned)
      Achievements::Providers::AchievementDefinition.new(
        external_id: trophy["trophyId"].to_s,
        name: trophy["trophyName"],
        description: trophy["trophyDetail"],
        icon_url: trophy["trophyIconUrl"],
        hidden: trophy["trophyHidden"] == true,
        tier: trophy["trophyType"],
        display_order: trophy["trophyId"].to_i,
        rarity: rarity(earned && earned["trophyEarnedRate"])
      )
    end

    def unlock(trophy)
      Achievements::Providers::ProviderUnlock.new(
        achievement_external_id: trophy["trophyId"].to_s,
        unlocked_at: parse_time(trophy["earnedDateTime"])
      )
    end

    # trophyEarnedRate is a string percentage such as "12.5".
    def rarity(value)
      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end

    def search_account(online_id)
      data = api_call(:post, SEARCH_URL, json: {
        searchTerm: online_id, domainRequests: [ { domain: "SocialAllAccounts" } ]
      })
      results = Array(data.dig("domainResponses", 0, "results"))
      match = results.map { |result| result["socialMetadata"] || {} }
        .find { |meta| meta["onlineId"].to_s.casecmp?(online_id) && meta["accountId"].present? }
      return unless match

      { external_id: match["accountId"].to_s, display_name: match["onlineId"], avatar_url: match["avatarUrl"] }
    end

    def profile_account(online_id)
      data = api_call(:get, format(PROFILE_URL, escape(online_id)), params: { fields: PROFILE_FIELDS })
      profile = data["profile"] || {}
      return if profile["accountId"].blank?

      avatar = Array(profile["avatarUrls"]).max_by { |entry| AVATAR_SIZES.index(entry["size"]) || -1 }
      { external_id: profile["accountId"].to_s, display_name: profile["onlineId"], avatar_url: avatar&.dig("avatarUrl") }
    rescue Achievements::Providers::NotFound
      nil
    end

    def played_titles(account_id)
      collected = []
      offset = 0

      loop do
        data = api_call(:get, format(PLAYED_URL, escape(account_id)),
          params: { categories: PLAYED_CATEGORIES, limit: PLAYED_PAGE, offset: offset })
        page = Array(data["titles"])
        collected.concat(page)

        offset += page.size
        break if page.empty? || offset >= data["totalItemCount"].to_i
      end

      collected
    rescue Achievements::Providers::Private, Achievements::Providers::NotFound
      []
    end

    # titleId -> npCommunicationId for the titles that have a trophy list,
    # from the cache first, then the bridge for the rest.
    def bridge(account_id, title_ids)
      title_ids = title_ids.compact.uniq
      known = cached_bridge(account_id, title_ids)
      missing = title_ids.reject { |id| known.key?(id) }

      missing.each_slice(BRIDGE_BATCH) do |batch|
        found = bridge_batch(account_id, batch)
        next if found.nil?

        found.each { |title_id, np_id| @cache.write(format(BRIDGE_CACHE_KEY, title_id), np_id, expires_in: BRIDGE_TTL) }
        (batch - found.keys).each do |title_id|
          @cache.write(format(BRIDGE_MISS_CACHE_KEY, account_id, title_id), true, expires_in: BRIDGE_MISS_TTL)
        end
        known.merge!(found)
      end

      known.compact
    end

    # titleId -> npCommunicationId, or nil (a cached miss) for each id the
    # cache knows.
    def cached_bridge(account_id, title_ids)
      hits = @cache.read_multi(*title_ids.map { |id| format(BRIDGE_CACHE_KEY, id) })
      misses = @cache.read_multi(*title_ids.map { |id| format(BRIDGE_MISS_CACHE_KEY, account_id, id) })
      title_ids.each_with_object({}) do |id, map|
        np_id = hits[format(BRIDGE_CACHE_KEY, id)]
        if np_id
          map[id] = np_id
        elsif misses[format(BRIDGE_MISS_CACHE_KEY, account_id, id)]
          map[id] = nil
        end
      end
    end

    # Nil when the batch failed (logged); the next read asks again.
    def bridge_batch(account_id, batch)
      data = api_call(:get, format(TITLE_TROPHY_TITLES_URL, escape(account_id)), params: { npTitleIds: batch.join(",") })
      Array(data["titles"]).each_with_object({}) do |entry, map|
        np_id = Array(entry["trophyTitles"]).first&.dig("npCommunicationId")
        map[entry["npTitleId"]] = np_id if np_id.present? && batch.include?(entry["npTitleId"])
      end
    rescue Error, Achievements::Providers::Private, Achievements::Providers::NotFound => error
      Rails.logger.warn("[PSN] could not bridge #{batch.size} titles to trophy lists: #{error.message}")
      nil
    end

    # ISO 8601 duration ("PT166H54M39S") -> whole minutes; 0 when blank or
    # unreadable.
    def duration_minutes(value)
      return 0 if value.blank?

      ActiveSupport::Duration.parse(value).to_i / 60
    rescue ActiveSupport::Duration::ISO8601Parser::ParsingError, ArgumentError
      0
    end

    def played_set(row)
      Achievements::Providers::PlayedSet.new(
        external_id: row["npCommunicationId"],
        np_service_name: row["npServiceName"],
        title: row["trophyTitleName"],
        platform_label: row["trophyTitlePlatform"],
        icon_url: row["trophyTitleIconUrl"],
        activity_at: parse_time(row["lastUpdatedDateTime"]),
        achievements_count: trophy_count(row["definedTrophies"])
      )
    end

    def trophy_count(counts)
      counts.is_a?(Hash) ? counts.values.sum(&:to_i) : nil
    end

    # --- auth -------------------------------------------------------------

    def access_token
      cached = @cache.read(ACCESS_TOKEN_CACHE_KEY)
      return cached if cached.present?

      data = refreshed_tokens || npsso_tokens
      token = data["access_token"]
      raise Error, "PSN token response had no access_token" if token.blank?

      store_tokens(data)
      clear_auth_expired
      token
    end

    # Exchanges a cached refresh token for new tokens. Returns nil (falling
    # back to the NPSSO) when there is none or Sony refuses it.
    def refreshed_tokens
      refresh_token = @cache.read(REFRESH_TOKEN_CACHE_KEY)
      return if refresh_token.blank?

      response = request(:post, TOKEN_URL, form: {
        refresh_token: refresh_token, grant_type: "refresh_token", token_format: "jwt", scope: SCOPE
      }, headers: { "Authorization" => CLIENT_AUTH })
      return parse_json(response.body) if response.success?

      @cache.delete(REFRESH_TOKEN_CACHE_KEY)
      nil
    end

    # NPSSO -> authorization code (read from the 302 Location, never followed)
    # -> tokens. A missing code or a refused exchange means the NPSSO expired.
    def npsso_tokens
      response = request(:get, AUTHORIZE_URL, params: {
        access_type: "offline", client_id: OAUTH_CLIENT_ID, response_type: "code",
        scope: SCOPE, redirect_uri: REDIRECT_URI
      }, headers: { "Cookie" => "npsso=#{npsso}" })
      code = code_from_location(response.headers["location"])
      auth_expired!("PSN authorize returned no code (NPSSO expired?)") if code.blank?

      response = request(:post, TOKEN_URL, form: {
        grant_type: "authorization_code", code: code, redirect_uri: REDIRECT_URI, token_format: "jwt"
      }, headers: { "Authorization" => CLIENT_AUTH })
      auth_expired!("PSN token exchange failed: HTTP #{response.status}") unless response.success?

      parse_json(response.body)
    end

    def store_tokens(data)
      ttl = [ data["expires_in"].to_i - TOKEN_SAFETY_MARGIN, TOKEN_SAFETY_MARGIN ].max
      @cache.write(ACCESS_TOKEN_CACHE_KEY, data["access_token"], expires_in: ttl)
      return if data["refresh_token"].blank?

      refresh_ttl = data["refresh_token_expires_in"].to_i - TOKEN_SAFETY_MARGIN
      @cache.write(REFRESH_TOKEN_CACHE_KEY, data["refresh_token"], expires_in: refresh_ttl) if refresh_ttl.positive?
    end

    # The custom-scheme Location is split by hand to avoid URI parsing quirks.
    def code_from_location(location)
      query = location.to_s.split("?", 2)[1]
      return if query.blank?

      URI.decode_www_form(query).to_h["code"]
    end

    # The first failure of an expiry records it and queues the staff alert;
    # repeats while it stays expired do neither.
    def auth_expired!(message)
      @cache.delete(ACCESS_TOKEN_CACHE_KEY)
      @cache.delete(REFRESH_TOKEN_CACHE_KEY)
      if hub_state.get(AUTH_EXPIRED_KEY).blank?
        expired_at = @clock.call.iso8601
        hub_state.set(AUTH_EXPIRED_KEY, expired_at)
        Achievements::PsnAuthAlerts.expired!(expired_at)
      end
      raise Achievements::Providers::AuthExpired, message
    end

    def clear_auth_expired
      expired_at = hub_state.get(AUTH_EXPIRED_KEY)
      return if expired_at.blank?

      hub_state.set(AUTH_EXPIRED_KEY, nil)
      Achievements::PsnAuthAlerts.restored!(expired_at: expired_at, restored_at: @clock.call.iso8601)
    end

    def hub_state
      @hub_state ||= AchievementHubState
    end

    def npsso
      @npsso ||= self.class.configured_npsso
      @npsso || auth_expired!("PSN NPSSO is not configured (credentials psn_npsso or PSN_NPSSO)")
    end

    # --- HTTP -------------------------------------------------------------

    # Authenticated call to a PSN API. Raises Private on an access-control
    # error (even on HTTP 200), NotFound on 404, RateLimited on 429 and
    # AuthExpired when a fresh token is still refused.
    def api_get(path, params = {})
      api_call(:get, "#{API_BASE_URL}#{path}", params: params)
    end

    def api_call(method, url, params: {}, json: nil)
      call = -> { request(method, url, params: params, json: json, headers: { "Authorization" => "Bearer #{access_token}" }) }
      response = call.call
      if response.status == 401
        # UNVERIFIED: that Sony answers a revoked or expired token with 401.
        # A cached token Sony has revoked: renew once before giving up.
        @cache.delete(ACCESS_TOKEN_CACHE_KEY)
        response = call.call
        auth_expired!("PSN refused a fresh access token (HTTP 401)") if response.status == 401
      end

      body = response.body.present? ? parse_json(response.body) : {}
      check_response!(response, body)
      body
    end

    def check_response!(response, body)
      error = body.is_a?(Hash) ? body["error"] : nil
      raise Achievements::Providers::Private, "PSN trophies are private" if access_control_error?(error) || response.status == 403
      # UNVERIFIED: that an unknown accountId or online ID answers 404.
      raise Achievements::Providers::NotFound, "PSN returned 404" if response.status == 404
      if response.status == 429
        raise Achievements::Providers::RateLimited.new("PSN rate limit reached", retry_after: retry_after_header(response))
      end
      raise Error, "PSN returned HTTP #{response.status}" unless response.success?
      raise Error, "PSN returned an error: #{error.inspect}" if error.present?
    end

    def access_control_error?(error)
      return false unless error.is_a?(Hash)

      error["code"].to_i == ACCESS_CONTROL_CODE || error["message"].to_s.match?(ACCESS_CONTROL_MESSAGE)
    end

    # One HTTP call with xergasa's protections: a single retry on a stale
    # connection (SSL EOF, reset) and a short bounded retry of transient
    # statuses. Returns the final Faraday::Response whatever its status.
    def request(method, url, params: {}, form: nil, json: nil, headers: {})
      attempt = 0
      stale_retried = false

      loop do
        attempt += 1
        begin
          response = http.run_request(method, url, request_body(form, json), request_headers(headers, form, json)) do |req|
            req.params.update(params) if params.present?
          end
        rescue *STALE_CONNECTION_ERRORS => e
          raise Error, "PSN request to #{URI(url).host} failed: #{e.message}" if stale_retried

          stale_retried = true
          retry
        end
        return response unless TRANSIENT_STATUSES.include?(response.status) && attempt < MAX_ATTEMPTS

        @sleeper.call([ retry_after_header(response) || BASE_BACKOFF_SECONDS * (2**(attempt - 1)),
                        MAX_BACKOFF_SECONDS ].min)
      end
    rescue Faraday::Error => e
      raise Error, "PSN request to #{URI(url).host} failed: #{e.class}: #{e.message}"
    end

    def request_body(form, json)
      return URI.encode_www_form(form) if form
      return json.to_json if json

      nil
    end

    def request_headers(headers, form, json)
      content_type = if form
        "application/x-www-form-urlencoded"
      elsif json
        "application/json"
      end
      content_type ? headers.merge("Content-Type" => content_type) : headers
    end

    # Sony's Retry-After, uncapped: a 429 hands it to the tick (which owns the
    # back-off); only the in-client sleep caps it at MAX_BACKOFF_SECONDS.
    def retry_after_header(response)
      seconds = Float(response.headers["Retry-After"], exception: false)
      seconds if seconds && seconds >= 0
    end

    def http
      @http ||= Faraday.new(headers: { "User-Agent" => USER_AGENT }) do |connection|
        connection.options.open_timeout = OPEN_TIMEOUT
        connection.options.read_timeout = READ_TIMEOUT
        connection.options.write_timeout = WRITE_TIMEOUT
      end
    end

    def parse_json(raw)
      JSON.parse(raw.to_s)
    rescue JSON::ParserError => e
      raise Error, "PSN returned a non-JSON response: #{e.message}"
    end

    def parse_time(value)
      return if value.blank?

      Time.iso8601(value).utc
    rescue ArgumentError
      nil
    end

    def escape(segment)
      ERB::Util.url_encode(segment.to_s)
    end
  end
end
