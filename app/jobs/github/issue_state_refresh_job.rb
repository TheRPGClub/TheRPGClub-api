# frozen_string_literal: true

module Github
  # Refreshes the cached issue states a Feedback Board read found missing
  # or stale (Github::IssueStateCache), so reads never wait on GitHub. One
  # runs at a time; states another run already refreshed are skipped. Each
  # lookup has a short timeout, and a run stops at the first failure: the
  # rest refresh on a later read. Each state read also updates whether the
  # Approved Feedback on that issue is Done (RpgClubFeedback.record_issue_state).
  class IssueStateRefreshJob < ApplicationJob
    queue_as :default
    limits_concurrency to: 1, key: "github_issue_states", duration: 5.minutes

    # pairs: [[repo, issue_number], ...]
    def perform(pairs)
      client = Client.new(timeout: IssueStateCache::LOOKUP_TIMEOUT_SECONDS)
      return unless client.configured?

      pairs.each do |repo, number|
        next if IssueStateCache.fresh?(repo, number)

        begin
          issue = client.issue(repo: repo, number: number)
          IssueStateCache.store(repo, number, issue&.state, reason: issue&.state_reason)
        rescue Client::RequestError, Client::ConfigurationError => error
          Rails.logger.warn("GitHub issue state for #{repo}##{number} failed: #{error.message}")
          IssueStateCache.failed(repo, number)
          break
        end
        record(repo, number, issue)
      end
    end

    private

    # A failure here is this pair's alone: it is logged and the run goes on.
    def record(repo, number, issue)
      RpgClubFeedback.record_issue_state(repo, number, issue&.state, issue&.state_reason)
    rescue StandardError => error
      Rails.logger.error("Recording GitHub issue state for #{repo}##{number} failed: #{error.class}: #{error.message}")
    end
  end
end
