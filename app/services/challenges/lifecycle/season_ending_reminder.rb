# frozen_string_literal: true

module Challenges
  module Lifecycle
    # The Season ending reminder (spec #376, "Lifecycle job"): DAYS_BEFORE
    # days before a Season's last day (or on its first day, for a shorter
    # Season), a `challenge_dm` "season_ending" to each member with an
    # unFinished (Active) Run of it who keeps Challenge DMs on. Sent once per
    # Season, on the first tick from that day until the Season ends; a Run
    # started after it is not reminded.
    module SeasonEndingReminder
      STEP = "season_ending_reminder"
      DAYS_BEFORE = 7

      def self.call(today:, **)
        taken = Lifecycle.taken(STEP, since: today - 1.year)
        Lifecycle.seasons(Challenge.all, today).each do |challenge, (starts_on, ends_on)|
          remind_on = remind_on(starts_on, ends_on)
          next if today < remind_on || taken.include?([ challenge.id, remind_on ])

          Lifecycle.once!(challenge, STEP, on: remind_on) do
            runs = ChallengeRun.active.where(challenge_id: challenge.id, season_starts_on: starts_on)
              .where(user_id: DirectMessages.reachable.select(:user_id))
            DirectMessages.season_ending!(challenge, runs, starts_on: starts_on, ends_on: ends_on, today: today)
          end
        end
      end

      def self.next_due_on(today)
        taken = Lifecycle.taken(STEP, since: today - 1.year)
        Lifecycle.seasons(Challenge.all, today).map do |challenge, (starts_on, ends_on)|
          remind_on = remind_on(starts_on, ends_on)
          next [ remind_on, today ].max unless taken.include?([ challenge.id, remind_on ])

          remind_on(*Lifecycle.next_season(challenge, ends_on))
        end.min
      end

      def self.remind_on(starts_on, ends_on) = [ ends_on - DAYS_BEFORE, starts_on ].max
    end
  end
end
