# frozen_string_literal: true

module Challenges
  module Lifecycle
    # The pick reminder (spec #376, "Lifecycle job"; ticket #384): DAYS_BEFORE
    # days before an Edition's pick deadline, a `challenge_dm` "pick_reminder"
    # to each Santa who hasn't picked yet, keeps Challenge DMs on and is still
    # in the server (a Santa who withdrew is no Santa any more). Sent once per
    # Edition, on the first tick from that day until the deadline; an Edition
    # drawn later than that day is reminded on its draw.
    module PickReminder
      STEP = "pick_reminder"
      DAYS_BEFORE = 2

      def self.call(today:, **)
        pending(today).each do |edition|
          remind_on = remind_on(edition)
          next if today < remind_on

          Lifecycle.once!(edition.challenge, STEP, on: remind_on) do
            santas = edition.signups.drawn.where(withdrawn_at: nil, picked_game_id: nil)
              .where(user_id: DirectMessages.reachable.select(:user_id))
            DirectMessages.pick_reminder!(edition, santas, today: today)
          end
        end
      end

      def self.next_due_on(today)
        pending(today).map { |edition| [ remind_on(edition), today ].max }.min
      end

      def self.remind_on(edition) = edition.pick_deadline_on - DAYS_BEFORE

      # The Editions taking picks on `today` whose reminder is not sent yet.
      def self.pending(today)
        taken = Lifecycle.taken(STEP, since: today - 1.year)
        ChallengeEdition.where(phase: "picking", picks_closed_at: nil).where("pick_deadline_on > ?", today)
          .preload(:challenge)
          .reject { |edition| taken.include?([ edition.challenge_id, remind_on(edition) ]) }
      end
    end
  end
end
