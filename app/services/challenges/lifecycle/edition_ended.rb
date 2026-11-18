# frozen_string_literal: true

module Challenges
  module Lifecycle
    # The Edition's end (GLOSSARY.md, "Edition"; ticket #384): on the next
    # reveal date, Challenges::Editions.end! Expires the Edition's
    # unFinished Runs, and its Santas are shown from then on. The Edition
    # leaving the revealed phase is what makes it happen once.
    module EditionEnded
      def self.call(now:, today:)
        due(today).find_each { |edition| Editions.end!(edition, now: now) }
      end

      def self.next_due_on(today)
        ends_on = due(nil).minimum(:ends_on)
        [ ends_on, today ].max if ends_on
      end

      def self.due(today)
        editions = ChallengeEdition.where(phase: "revealed")
        today ? editions.where(ends_on: ..today) : editions
      end
    end
  end
end
