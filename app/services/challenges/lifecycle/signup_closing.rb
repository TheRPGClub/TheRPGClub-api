# frozen_string_literal: true

module Challenges
  module Lifecycle
    # Sign-up closing soon: DAYS_BEFORE days before an Edition's sign-up
    # cutoff, a `challenge_announce` "signup_closing" with the days left, once
    # per Edition, on the first tick from that day until the cutoff. Not for
    # hidden Challenges, nor when the Edition opened later than that day (its
    # opening post already gave the cutoff).
    module SignupClosing
      STEP = "signup_closing"
      DAYS_BEFORE = 3

      def self.call(today:, **)
        pending(today).each do |edition|
          announce_on = announce_on(edition)
          next if today < announce_on

          Lifecycle.once!(edition.challenge, STEP, on: announce_on) do
            next if announce_on < edition.signup_opens_on

            Announcements.signup_closing!(edition, today: today)
          end
        end
      end

      def self.next_due_on(today)
        pending(today).map { |edition| [ announce_on(edition), today ].max }.min
      end

      def self.announce_on(edition) = edition.signup_cutoff_on - DAYS_BEFORE

      # The visible Challenges' Editions in sign-up on `today` whose closing
      # is not announced yet.
      def self.pending(today)
        taken = Lifecycle.taken(STEP, since: today - 1.year)
        Editions.in_signup_on(today, Challenge.visible).preload(:challenge)
          .reject { |edition| taken.include?([ edition.challenge_id, announce_on(edition) ]) }
      end
    end
  end
end
