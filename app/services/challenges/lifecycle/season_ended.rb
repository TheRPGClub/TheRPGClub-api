# frozen_string_literal: true

module Challenges
  module Lifecycle
    # A Season ending (GLOSSARY.md, "Expired"): the day after a Season's last
    # day, every Run of it still Active becomes Expired. Finished and
    # Abandoned Runs are left as they are.
    module SeasonEnded
      def self.call(today:, now:)
        overdue(today).update_all(status: "expired", ended_at: now, updated_at: now)
      end

      def self.next_due_on(today)
        return today if overdue(today).exists?

        Lifecycle.seasons(Challenge.all, today).map { |_challenge, (_starts_on, ends_on)| ends_on + 1 }.min
      end

      # The Active Runs whose Season has ended by `today`.
      def self.overdue(today) = ChallengeRun.active.where(season_ends_on: ...today)
    end
  end
end
