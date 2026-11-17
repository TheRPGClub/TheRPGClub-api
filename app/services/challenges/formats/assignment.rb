# frozen_string_literal: true

module Challenges
  module Formats
    # The Assignment Challenge Format (GLOSSARY.md, "Assignment"): Secret
    # Santa, where another member picks the game from a member's backlog. It
    # runs in yearly Editions (Challenges::Editions) on the Challenge's
    # calendar: the sign-up cutoff, the pick deadline and the reveal date, each
    # a month and day, coming in that order through the year. They default to
    # the Secret Santa ones (DEFAULTS), with the reveal on 25 December.
    #
    # Request and response object:
    #   { signup_cutoff: "12-01", pick_deadline: "12-15", reveal: "12-25" }
    # The response adds `edition`, the latest Edition (or null before one
    # opens), as ChallengeEditionResource's summary.
    #
    # Members never start an Assignment Run themselves: they sign up for an
    # Edition, and the draw gives each drawn member a Run of it.
    module Assignment
      KEY = "assignment"
      FIELDS = %w[signup_cutoff pick_deadline reveal].freeze
      DEFAULTS = { "signup_cutoff" => "12-01", "pick_deadline" => "12-15", "reveal" => "12-25" }.freeze

      # The Edition calendar, as Challenges::Schedule::MonthDay values.
      Calendar = Data.define(:signup_cutoff, :pick_deadline, :reveal) do
        # The dates of the Edition revealed in `year`: the pick deadline is the
        # last one before the reveal, the cutoff the last one before that, and
        # sign-up opens the day after the previous reveal (or on `opens_from`,
        # the day the Challenge was created, if later). It ends on the next
        # reveal date.
        def edition(year, opens_from: nil)
          reveal_on = on(reveal, year)
          pick_deadline_on = last_before(pick_deadline, reveal_on)
          signup_cutoff_on = last_before(signup_cutoff, pick_deadline_on)
          EditionDates.new(year: year, signup_opens_on: [ on(reveal, year - 1) + 1, opens_from ].compact.max,
            signup_cutoff_on: signup_cutoff_on, pick_deadline_on: pick_deadline_on, reveal_on: reveal_on,
            ends_on: on(reveal, year + 1))
        end

        # The year of the Edition whose reveal is the first on or after `date`.
        def year_on(date) = on(reveal, date.year) >= date ? date.year : date.year + 1

        # Whether the three dates come in order through the year: the cutoff
        # after the previous reveal.
        def ordered?
          dates = edition(2001)
          dates.signup_cutoff_on > dates.signup_opens_on
        end

        def to_h = { signup_cutoff: signup_cutoff.to_s, pick_deadline: pick_deadline.to_s, reveal: reveal.to_s }

        private

        def on(month_day, year) = Date.new(year, month_day.month, month_day.day)

        def last_before(month_day, date)
          day = on(month_day, date.year)
          day < date ? day : on(month_day, date.year - 1)
        end
      end

      EditionDates = Data.define(:year, :signup_opens_on, :signup_cutoff_on, :pick_deadline_on, :reveal_on, :ends_on)

      def self.load(challenge)
        Calendar.new(
          signup_cutoff: month_day(challenge.signup_cutoff_month, challenge.signup_cutoff_day),
          pick_deadline: month_day(challenge.pick_deadline_month, challenge.pick_deadline_day),
          reveal: month_day(challenge.reveal_month, challenge.reveal_day)
        )
      end

      def self.month_day(month, day) = month && day ? Schedule::MonthDay.new(month: month, day: day) : nil
      private_class_method :month_day

      # On create the calendar may be left out, or given in part: what is
      # missing is the Secret Santa default.
      def self.parse(input, base: nil)
        raise Invalid, "assignment must be an object" unless input.nil? || input.is_a?(Hash)

        input ||= {}
        days = FIELDS.to_h do |field|
          day = if input.key?(field)
            parse_day(input[field], field)
          else
            base&.public_send(field) || Schedule::MonthDay.parse(DEFAULTS.fetch(field), field)
          end
          [ field.to_sym, day ]
        end
        Calendar.new(**days)
      end

      def self.parse_day(value, field)
        day = Schedule::MonthDay.parse(value, "assignment #{field}")
        raise Invalid, "assignment #{field} must be a day every year has" if day.month == 2 && day.day == 29

        day
      end
      private_class_method :parse_day

      def self.errors(calendar)
        days = calendar.to_h.values
        return [ "assignment signup_cutoff, pick_deadline and reveal must be different days" ] if days.uniq.size < 3
        return [] if calendar.ordered?

        [ "assignment signup_cutoff, pick_deadline and reveal must come in that order through the year" ]
      end

      # Writes the calendar, then opens the Edition due today (on create), or
      # moves an Edition still in sign-up that nobody has joined to the new
      # dates (Challenges::Editions.calendar_changed!).
      def self.apply!(challenge, calendar)
        changed = load(challenge) != calendar
        challenge.update_columns(
          signup_cutoff_month: calendar.signup_cutoff.month, signup_cutoff_day: calendar.signup_cutoff.day,
          pick_deadline_month: calendar.pick_deadline.month, pick_deadline_day: calendar.pick_deadline.day,
          reveal_month: calendar.reveal.month, reveal_day: calendar.reveal.day
        )
        Editions.calendar_changed!(challenge) if changed
        Editions.open_due!(challenge, Challenges.today)
      end

      def self.rules(calendar) = calendar.to_h

      def self.as_json(challenge, calendar, **)
        edition = challenge.editions.max_by(&:year)
        calendar.to_h.merge(edition: edition && ChallengeEditionResource.summary(edition))
      end

      # Starting a Run (Challenges::Runs.start!): refused, since an
      # Assignment Run comes only from an Edition's draw.
      def self.run_attributes(*, **)
        raise RunRefused.new("signup_required", SIGNUP_REQUIRED)
      end

      SIGNUP_REQUIRED = "Secret Santa Runs come from the draw: sign up for the Edition instead."

      def self.notices(_run) = []

      # Run progress (Challenges::Progress): the Run's only game is the one
      # picked for its member, from the reveal on; until then it counts
      # nothing, so the pick stays a surprise. The pick stands even if the
      # game leaves their backlog.
      def self.count(run, plays)
        game_id = run.edition&.revealed? && run.assignment&.picked_game_id
        return [] unless game_id

        [ plays.counted(game_id) ].compact
      end

      # The Run is Finished when its assigned game is Cleared.
      def self.summary(_run, entries)
        Progress::Summary.new(in_progress: entries.count { |entry| entry.state == "in_progress" },
          cleared: entries.count { |entry| entry.state == "cleared" }, target: 1,
          goal_reached: entries.any? { |entry| entry.state == "cleared" })
      end
    end
  end
end
