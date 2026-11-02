# frozen_string_literal: true

module Github
  # An issue's state ("open" or "closed") for the Suggestion Board, read from
  # GitHub on view and kept in the Rails cache for TTL so the board does not
  # call GitHub on every view. nil when the GitHub App is not configured, the
  # issue is gone, or GitHub fails; a failure is cached for FAILURE_TTL.
  #
  # One request never makes many sequential GitHub calls: each lookup has a
  # short timeout, a request makes at most MAX_LOOKUPS_PER_REQUEST uncached
  # lookups, and it makes none after one fails. A skipped lookup is nil and
  # is not cached, so it fills on a later view.
  module IssueStateCache
    TTL = 10.minutes
    FAILURE_TTL = 10.minutes
    LOOKUP_TIMEOUT_SECONDS = 3
    MAX_LOOKUPS_PER_REQUEST = 5

    def self.fetch(repo, number)
      return if repo.blank? || number.blank?

      key = key_for(repo, number)
      cached = Rails.cache.read(key)
      return cached[:state] if cached

      lookups = Current.github_issue_lookups.to_i
      return if lookups >= MAX_LOOKUPS_PER_REQUEST

      client = Client.new(timeout: LOOKUP_TIMEOUT_SECONDS)
      return unless client.configured?

      Current.github_issue_lookups = lookups + 1
      begin
        state = client.issue_state(repo: repo, number: number)
        store(repo, number, state)
      rescue Client::RequestError, Client::ConfigurationError => error
        Rails.logger.warn("GitHub issue state for #{repo}##{number} failed: #{error.message}")
        state = nil
        Current.github_issue_lookups = MAX_LOOKUPS_PER_REQUEST
        Rails.cache.write(key, { state: nil }, expires_in: FAILURE_TTL)
      end
      state
    end

    # Seeds the cache with a state already known (a just-created issue is open).
    def self.store(repo, number, state)
      Rails.cache.write(key_for(repo, number), { state: state }, expires_in: TTL)
    end

    def self.key_for(repo, number)
      "github_issue_state/v1/#{repo}/#{number}"
    end
  end
end
