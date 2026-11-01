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

    # Used until AchievementHubState (api-01) exists: auth expiry is only logged.
    module NullHubState
      def self.get(_key) = nil

      def self.set(key, value)
        Rails.logger.warn("[PSN] #{key}=#{value.inspect} (no AchievementHubState to record it in)")
      end
    end

    def initialize(npsso: nil, http: nil, cache: nil, hub_state: nil, sleeper: nil, clock: nil)
      @npsso = npsso
      @http = http
      @cache = cache || Rails.cache
      @hub_state = hub_state
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      @clock = clock || -> { Time.current }
    end

    # The member's played Achievement Sets (their trophy titles), newest first.
    # With `since`, stops at the first title last updated before it: the list
    # is sorted by lastUpdatedDateTime descending (research §4).
    def played_sets(account_id, since: nil)
      collected = []
      offset = 0

      loop do
        data = api_get("/trophy/v1/users/#{escape(account_id)}/trophyTitles", { limit: TITLES_PAGE, offset: offset })
        page = Array(data["trophyTitles"])
        sets = page.map { |row| played_set(row) }
        fresh = since ? sets.take_while { |set| set.last_played_at.nil? || set.last_played_at >= since } : sets
        collected.concat(fresh)

        offset += page.size
        break if page.empty? || fresh.size < sets.size || offset >= data["totalItemCount"].to_i
      end

      collected
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

    private

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

    def played_set(row)
      Achievements::Providers::PlayedSet.new(
        external_id: row["npCommunicationId"],
        np_service_name: row["npServiceName"],
        title: row["trophyTitleName"],
        platform_label: row["trophyTitlePlatform"],
        icon_url: row["trophyTitleIconUrl"],
        last_played_at: parse_time(row["lastUpdatedDateTime"]),
        earned_count: trophy_count(row["earnedTrophies"]),
        total_count: trophy_count(row["definedTrophies"])
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

    def auth_expired!(message)
      @cache.delete(ACCESS_TOKEN_CACHE_KEY)
      @cache.delete(REFRESH_TOKEN_CACHE_KEY)
      hub_state.set(AUTH_EXPIRED_KEY, @clock.call.iso8601) if hub_state.get(AUTH_EXPIRED_KEY).blank?
      raise Achievements::Providers::AuthExpired, message
    end

    def clear_auth_expired
      hub_state.set(AUTH_EXPIRED_KEY, nil) if hub_state.get(AUTH_EXPIRED_KEY).present?
    end

    # Seam until api-01's AchievementHubState is merged.
    def hub_state
      @hub_state ||= Object.const_defined?(:AchievementHubState) ? ::AchievementHubState : NullHubState
    end

    def npsso
      @npsso ||= Rails.application.credentials.psn_npsso.presence || ENV["PSN_NPSSO"].presence
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
      raise Achievements::Providers::NotFound, "PSN returned 404" if response.status == 404
      if response.status == 429
        raise Achievements::Providers::RateLimited.new("PSN rate limit reached", retry_after: retry_after(response))
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

        @sleeper.call(retry_after(response) || [ BASE_BACKOFF_SECONDS * (2**(attempt - 1)), MAX_BACKOFF_SECONDS ].min)
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

    def retry_after(response)
      seconds = Float(response.headers["Retry-After"], exception: false)
      [ seconds, MAX_BACKOFF_SECONDS ].min if seconds && seconds >= 0
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
