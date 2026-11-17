# frozen_string_literal: true

module Challenges
  # When a Challenge is Open (GLOSSARY.md, "Always Open", "Seasonal",
  # "Season"). Dates are the club's (Challenges.today).
  #
  # Always Open: Open until its end date, inclusive, or for good without one.
  # Seasonal: Open from its Season's start to its end, inclusive, every year.
  # A Season whose end comes before its start in the calendar crosses the new
  # year (1 December to 28 February).
  #
  # Challenge.open_on is the same rule in SQL, for lists.
  module Schedule
    MONTH_DAY = /\A(\d{2})-(\d{2})\z/

    # A month and day of the year, written "MM-DD" on the API.
    MonthDay = Data.define(:month, :day) do
      # Parses "MM-DD"; raises Challenges::Invalid for anything else or a day
      # no year has (29 February is allowed).
      def self.parse(value, field)
        match = MONTH_DAY.match(value.to_s)
        raise Invalid, "#{field} must be a month and day as MM-DD" unless match

        month, day = match.captures.map(&:to_i)
        raise Invalid, "#{field} is not a day of the year" unless Date.valid_date?(2000, month, day)

        new(month: month, day: day)
      end

      def ordinal = (month * 100) + day

      def to_s = format("%<month>02d-%<day>02d", month: month, day: day)
    end

    AlwaysOpen = Data.define(:ends_on) do
      def open_on?(date) = ends_on.nil? || date <= ends_on

      def as_json(*) = { schedule: "always_open", ends_on: ends_on&.iso8601, season: nil }
    end

    Seasonal = Data.define(:starts, :ends) do
      def crosses_new_year? = starts.ordinal > ends.ordinal

      def open_on?(date)
        today = (date.month * 100) + date.day
        crosses_new_year? ? today >= starts.ordinal || today <= ends.ordinal : today.between?(starts.ordinal, ends.ordinal)
      end

      def as_json(*)
        { schedule: "seasonal", ends_on: nil,
          season: { start: starts.to_s, end: ends.to_s, crosses_new_year: crosses_new_year? } }
      end
    end

    def self.for(challenge)
      return AlwaysOpen.new(ends_on: challenge.ends_on) unless challenge.seasonal?

      Seasonal.new(
        starts: MonthDay.new(month: challenge.season_start_month, day: challenge.season_start_day),
        ends: MonthDay.new(month: challenge.season_end_month, day: challenge.season_end_day)
      )
    end

    # The columns for a Season given as { "start" => "MM-DD", "end" => "MM-DD" }.
    def self.season_columns(season)
      raise Invalid, "season must be an object with start and end" unless season.is_a?(Hash)

      starts = MonthDay.parse(season["start"], "season start")
      ends = MonthDay.parse(season["end"], "season end")
      raise Invalid, "season start and end must be different days" if starts == ends

      { season_start_month: starts.month, season_start_day: starts.day,
        season_end_month: ends.month, season_end_day: ends.day }
    end

    # Why a Seasonal Challenge's stored Season is not one (empty when it is).
    def self.season_errors(challenge)
      values = [ challenge.season_start_month, challenge.season_start_day, challenge.season_end_month,
        challenge.season_end_day ]
      return [ "is required for a Seasonal Challenge" ] if values.any?(&:nil?)

      starts = [ challenge.season_start_month, challenge.season_start_day ]
      ends = [ challenge.season_end_month, challenge.season_end_day ]
      errors = []
      errors << "start is not a day of the year" unless Date.valid_date?(2000, *starts)
      errors << "end is not a day of the year" unless Date.valid_date?(2000, *ends)
      errors << "start and end must be different days" if starts == ends
      errors
    end
  end
end
