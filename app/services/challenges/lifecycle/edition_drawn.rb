# frozen_string_literal: true

module Challenges
  module Lifecycle
    # The draw (spec #376, "Secret Santa draw"): from an Edition's sign-up
    # cutoff, Challenges::Editions.draw! closes its sign-up, leaves out the
    # members below the backlog minimum, draws the rest into one circle with
    # a Run each (or cancels the Edition), and announces it. The Edition
    # leaving sign-up is what makes it happen once.
    module EditionDrawn
      def self.call(now:, today:)
        due(today).find_each { |edition| Editions.draw!(edition, now: now) }
      end

      def self.next_due_on(today)
        cutoff = due(nil).minimum(:signup_cutoff_on)
        [ cutoff, today ].max if cutoff
      end

      # Assignment Challenges' Editions still in sign-up, those whose cutoff
      # came by `today` (all of them when nil).
      def self.due(today)
        editions = ChallengeEdition.in_signup
          .where(challenge_id: Challenge.where(challenge_format: Formats::Assignment::KEY).select(:id))
        today ? editions.where(signup_cutoff_on: ..today) : editions
      end
    end
  end
end
