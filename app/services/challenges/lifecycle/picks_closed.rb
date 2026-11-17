# frozen_string_literal: true

module Challenges
  module Lifecycle
    # The pick deadline (spec #376, "Secret Santa draw"; ticket #384): from
    # an Edition's pick deadline, Challenges::Picks.close! gives a random pick
    # to every recipient whose Santa didn't pick, withdrew or left the
    # server. `picks_closed_at` makes it happen once.
    module PicksClosed
      def self.call(now:, today:)
        due(today).find_each { |edition| Picks.close!(edition, now: now) }
      end

      def self.next_due_on(today)
        deadline = due(nil).minimum(:pick_deadline_on)
        [ deadline, today ].max if deadline
      end

      # The drawn Editions whose picks are still open, those whose deadline
      # came by `today` (all of them when nil).
      def self.due(today)
        editions = ChallengeEdition.where(phase: "picking", picks_closed_at: nil)
        today ? editions.where(pick_deadline_on: ..today) : editions
      end
    end
  end
end
