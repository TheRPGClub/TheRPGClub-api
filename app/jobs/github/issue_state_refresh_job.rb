# frozen_string_literal: true

module Github
  # Refreshes the cached issue states a Suggestion Board read found missing
  # or stale (Github::IssueStateCache), so reads never wait on GitHub. One
  # runs at a time; states another run already refreshed are skipped. Each
  # lookup has a short timeout, and a run stops at the first failure: the
  # rest refresh on a later read.
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
          IssueStateCache.store(repo, number, client.issue_state(repo: repo, number: number))
        rescue Client::RequestError, Client::ConfigurationError => error
          Rails.logger.warn("GitHub issue state for #{repo}##{number} failed: #{error.message}")
          IssueStateCache.failed(repo, number)
          break
        end
      end
    end
  end
end
