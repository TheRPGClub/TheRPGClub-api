# frozen_string_literal: true

module Challenges
  module Lifecycle
    # A Seasonal Challenge's Season opening (GLOSSARY.md, "Season"): a
    # `challenge_announce` "season_opened", once per Season, from its first
    # day for as long as it is Open. Hidden Challenges are not announced (a
    # Season still Open when one is unhidden is announced then), and nor is a
    # Season already Open when its Challenge was created, whose creation was
    # announced instead.
    module SeasonOpened
      STEP = "season_opened"

      def self.call(today:, **)
        taken = Lifecycle.taken(STEP, since: today - 1.year)
        Lifecycle.seasons(Challenge.visible, today).each do |challenge, (starts_on, ends_on)|
          next if today < starts_on || taken.include?([ challenge.id, starts_on ])

          Lifecycle.once!(challenge, STEP, on: starts_on) do
            next if Challenges.today(challenge.created_at) >= starts_on

            Announcements.season_opened!(challenge, starts_on: starts_on, ends_on: ends_on)
          end
        end
      end

      def self.next_due_on(today)
        taken = Lifecycle.taken(STEP, since: today - 1.year)
        Lifecycle.seasons(Challenge.visible, today).map do |challenge, (starts_on, ends_on)|
          if taken.include?([ challenge.id, starts_on ])
            Lifecycle.next_season(challenge, ends_on).first
          else
            [ starts_on, today ].max
          end
        end.min
      end
    end
  end
end
