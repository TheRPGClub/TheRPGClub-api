# frozen_string_literal: true

module Challenges
  module Lifecycle
    # The new year's slot (GLOSSARY.md, "Slots", "Caught Up"): on 1 January
    # every Slots range that ends at the current year gains a slot. The slot
    # itself is worked out when read, so a Run stops being Caught Up by
    # itself; this step refreshes the Active Runs of those Challenges once a
    # year, so a Cleared game already waiting for a slot fills the new year
    # without waiting for the member's next write, and a Run Caught Up again
    # that way is announced (Challenges.refresh_runs!).
    #
    # A Challenge created during the year is recorded on its first sweep, so
    # it next comes due the following 1 January.
    module NewYearSlot
      STEP = "new_year_slot"

      def self.call(today:, **)
        new_year = today.beginning_of_year
        taken = Lifecycle.taken(STEP, since: new_year)
        growing.find_each do |challenge|
          next if taken.include?([ challenge.id, new_year ])

          Lifecycle.once!(challenge, STEP, on: new_year) do
            ChallengeRun.active.where(challenge_id: challenge.id).distinct.pluck(:user_id)
              .each { |user_id| Challenges.refresh_runs!(user_id) }
          end
        end
      end

      def self.next_due_on(today)
        ids = growing.ids
        return if ids.empty?

        new_year = today.beginning_of_year
        taken = Lifecycle.taken(STEP, since: new_year)
        ids.all? { |id| taken.include?([ id, new_year ]) } ? new_year.next_year : today
      end

      # Slots Challenges whose range ends at the current year and that have
      # not reached their end date.
      def self.growing = Challenge.where(challenge_format: "slots", slots_last_year: nil, ended_at: nil)
    end
  end
end
