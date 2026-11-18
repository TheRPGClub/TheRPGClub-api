# frozen_string_literal: true

module Challenges
  module Lifecycle
    # The reveal (spec #376, "Secret Santa"; ticket #384): from an Edition's
    # reveal date, Challenges::Editions.reveal! reveals every assignment,
    # gives each recipient's Run its goal and announces it. The Edition
    # leaving the picking phase is what makes it happen once.
    module EditionRevealed
      def self.call(now:, today:)
        due(today).find_each { |edition| Editions.reveal!(edition, now: now) }
      end

      def self.next_due_on(today)
        reveal = due(nil).minimum(:reveal_on)
        [ reveal, today ].max if reveal
      end

      def self.due(today)
        editions = ChallengeEdition.where(phase: "picking")
        today ? editions.where(reveal_on: ..today) : editions
      end
    end
  end
end
