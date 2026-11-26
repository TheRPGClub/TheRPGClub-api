# frozen_string_literal: true

module Github
  # An issue's state ("open" or "closed", with GitHub's reason for it) for
  # the Feedback Board, kept in
  # the Rails cache. nil when the GitHub App is not configured, the issue is
  # gone, GitHub fails, or the state hasn't been read yet.
  #
  # Reads never call GitHub. They read every state a page needs in one cache
  # read (`states_for`; in production the cache is a database, so this is one
  # round trip, not one per Feedback), and queue Github::IssueStateRefreshJob
  # for any state that is missing or older than TTL. A stale state keeps being
  # served (for up to KEEP) while it refreshes, so the board doesn't blank out
  # every TTL.
  module IssueStateCache
    # A state is refreshed once it is this old.
    TTL = 10.minutes
    # After a failed lookup, the next try waits this long.
    FAILURE_TTL = 10.minutes
    # A stale state is still served for this long while it refreshes.
    KEEP = 1.day
    LOOKUP_TIMEOUT_SECONDS = 3

    # { [repo, number] => state } for each pair, from one cache read; queues
    # one refresh for the pairs that are missing or stale.
    def self.states_for(pairs)
      pairs = pairs.reject { |repo, number| repo.blank? || number.blank? }.uniq
      return {} if pairs.empty?

      entries = Rails.cache.read_multi(*pairs.map { |pair| key_for(*pair) })
      stale = pairs.reject { |pair| fresh_entry?(entries[key_for(*pair)]) }
      IssueStateRefreshJob.perform_later(stale) if stale.any?

      pairs.index_with { |pair| entries[key_for(*pair)]&.dig(:state) }
    end

    def self.state_for(repo, number)
      states_for([ [ repo, number ] ])[[ repo, number ]]
    end

    def self.fresh?(repo, number)
      fresh_entry?(Rails.cache.read(key_for(repo, number)))
    end

    # Records a state just read (or already known: a just-created issue is
    # open), with GitHub's `reason` for it (a closed issue's "completed" or
    # "not_planned"; see Github::Client::Issue).
    def self.store(repo, number, state, reason: nil, fresh_for: TTL)
      Rails.cache.write(key_for(repo, number), { state: state, reason: reason, fresh_until: fresh_for.from_now },
        expires_in: KEEP)
    end

    # Records a failed lookup: keeps whatever state (and reason) was known,
    # and waits FAILURE_TTL before the next try.
    def self.failed(repo, number)
      known = Rails.cache.read(key_for(repo, number))
      store(repo, number, known&.dig(:state), reason: known&.dig(:reason), fresh_for: FAILURE_TTL)
    end

    # A closed state cached before reasons were kept (no `:reason` key) is
    # stale, so the refresh reads its reason and settles whether its
    # Feedback is Done (RpgClubFeedback.record_issue_state).
    def self.fresh_entry?(entry)
      return false unless entry.is_a?(Hash) && entry[:fresh_until].present? && entry[:fresh_until] > Time.current

      entry[:state] != "closed" || entry.key?(:reason)
    end
    private_class_method :fresh_entry?

    def self.key_for(repo, number)
      "github_issue_state/v2/#{repo}/#{number}"
    end
  end
end
