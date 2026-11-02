# frozen_string_literal: true

module Github
  # An issue's state ("open" or "closed") for the Suggestion Board, read from
  # GitHub on view and kept in the Rails cache for TTL so the board does not
  # call GitHub on every view. nil when the GitHub App is not configured, the
  # issue is gone, or GitHub fails; a failure is cached for FAILURE_TTL only.
  module IssueStateCache
    TTL = 10.minutes
    FAILURE_TTL = 1.minute

    def self.fetch(repo, number)
      return if repo.blank? || number.blank?

      key = key_for(repo, number)
      cached = Rails.cache.read(key)
      return cached[:state] if cached

      client = Client.new
      return unless client.configured?

      begin
        state = client.issue_state(repo: repo, number: number)
        store(repo, number, state)
      rescue Client::RequestError, Client::ConfigurationError => error
        Rails.logger.warn("GitHub issue state for #{repo}##{number} failed: #{error.message}")
        state = nil
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
