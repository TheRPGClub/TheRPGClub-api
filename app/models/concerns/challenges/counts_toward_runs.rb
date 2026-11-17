# frozen_string_literal: true

module Challenges
  # For the records Run progress is made from (docs/adr/0009): Game
  # Completions and Now Playing entries. After every commit that creates,
  # updates or deletes one, the member's Runs are brought up to date
  # (Challenges.refresh_runs!), whatever wrote it: the controllers, the
  # Completionator import or the bot through them. A record moved to another
  # member refreshes both.
  #
  # Writes that skip callbacks (`delete_all`, `update_columns`, `insert_all`)
  # never get here, so their callers either share a transaction with a
  # write that does, or call Challenges.refresh_runs! themselves.
  module CountsTowardRuns
    extend ActiveSupport::Concern

    included do
      after_commit :refresh_challenge_runs
    end

    private

    # The write has committed by now, so a failed refresh is reported rather
    # than failing it; the member's next write brings the Runs up to date.
    def refresh_challenge_runs
      [ user_id, *previous_changes["user_id"] ].compact.uniq.each do |id|
        Challenges.refresh_runs!(id)
      rescue StandardError => e
        raise if Rails.env.test?

        Rails.error.report(e, handled: true, context: { user_id: id })
      end
    end
  end
end
