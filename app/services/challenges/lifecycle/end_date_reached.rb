# frozen_string_literal: true

module Challenges
  module Lifecycle
    # An Always Open Challenge reaching its end date (GLOSSARY.md, "Always
    # Open", "Expired"): the day after its last Open day, every Run of it
    # still Active becomes Expired, and the Challenge Closes for good
    # (`ended_at`), so its end date can no longer move to reopen it
    # (Challenges::Form). Finished and Abandoned Runs are left as they are.
    module EndDateReached
      def self.call(today:, now:)
        reached.where(ends_on: ...today).find_each do |challenge|
          Challenge.transaction do
            ChallengeRun.active.where(challenge_id: challenge.id)
              .update_all(status: "expired", ended_at: now, updated_at: now)
            challenge.update_columns(ended_at: now)
          end
        end
      end

      def self.next_due_on(today)
        last_day = reached.minimum(:ends_on)
        [ last_day + 1, today ].max if last_day
      end

      # Always Open Challenges with an end date that have not ended yet.
      def self.reached = Challenge.where(schedule: "always_open", ended_at: nil).where.not(ends_on: nil)
    end
  end
end
