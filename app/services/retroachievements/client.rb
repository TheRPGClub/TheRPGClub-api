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
    class ConfigurationError < StandardError; end
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

    private

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
