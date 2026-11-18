# frozen_string_literal: true

module Challenges
  module Lifecycle
    # An Edition opening (GLOSSARY.md, "Edition"): each Assignment
    # Challenge's next Edition opens by itself the day after the previous
    # reveal (Challenges::Editions.open_due!), and a `challenge_announce`
    # "signup_opened" goes out once per Edition while its sign-up is open.
    # Hidden Challenges are not announced (one unhidden during sign-up is
    # announced then), and nor is an Edition that opened with its Challenge,
    # whose creation was announced instead.
    module EditionOpened
      STEP = "signup_opened"

      def self.call(today:, **)
        challenges.each { |challenge| Editions.open_due!(challenge, today) }

        unannounced(today).each do |edition|
          challenge = edition.challenge
          Lifecycle.once!(challenge, STEP, on: edition.signup_opens_on) do
            next if Challenges.today(challenge.created_at) >= edition.signup_opens_on

            Announcements.signup_opened!(edition)
          end
        end
      end

      def self.next_due_on(today)
        return today if unannounced(today).any?

        challenges.map do |challenge|
          due = Editions.due(challenge, today)
          next today if due && challenge.editions.none? { |edition| edition.year == due.year }

          Editions.next_opening_on(challenge, today)
        end.min
      end

      def self.challenges = Challenge.where(challenge_format: Formats::Assignment::KEY).preload(:editions)

      # The visible Challenges' Editions in sign-up on `today` whose opening
      # is not announced yet.
      def self.unannounced(today)
        taken = Lifecycle.taken(STEP, since: today - 1.year)
        Editions.in_signup_on(today, Challenge.visible).preload(:challenge)
          .reject { |edition| taken.include?([ edition.challenge_id, edition.signup_opens_on ]) }
      end
    end
  end
end
