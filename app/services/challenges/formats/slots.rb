# frozen_string_literal: true

module Challenges
  module Formats
    # The Slots Challenge Format (GLOSSARY.md, "Slots"): one slot per release
    # year in a range, such as Years Alive. The range's first year is a fixed
    # year or each member's birth year (`slots_first_year` null), and its last
    # year a fixed year or the current year (`slots_last_year` null), so that
    # range gains a slot every 1 January.
    #
    # Request and response object:
    #   { first_year: 1990 | "birth_year", last_year: 1999 | "current_year" }
    module Slots
      KEY = "slots"
      BIRTH_YEAR = "birth_year"
      CURRENT_YEAR = "current_year"
      YEARS = (BirthDates::EARLIEST.year..2100)

      Settings = Data.define(:first_year, :last_year) do
        def birth_year? = first_year.nil?

        def growing? = last_year.nil?
      end

      def self.load(challenge)
        Settings.new(first_year: challenge.slots_first_year, last_year: challenge.slots_last_year)
      end

      def self.parse(input, base: nil)
        raise Invalid, "slots is required for a Slots Challenge" unless input.is_a?(Hash) || base
        raise Invalid, "slots must be an object" unless input.nil? || input.is_a?(Hash)

        input ||= {}
        if base.nil?
          raise Invalid, %(slots first_year is required: a year or "#{BIRTH_YEAR}") unless input.key?("first_year")
          raise Invalid, %(slots last_year is required: a year or "#{CURRENT_YEAR}") unless input.key?("last_year")
        end

        Settings.new(
          first_year: input.key?("first_year") ? parse_year(input["first_year"], "first_year", BIRTH_YEAR) : base.first_year,
          last_year: input.key?("last_year") ? parse_year(input["last_year"], "last_year", CURRENT_YEAR) : base.last_year
        )
      end

      def self.parse_year(value, field, word)
        return nil if value == word

        year = Integer(value.to_s, 10)
        raise ArgumentError unless YEARS.cover?(year)

        year
      rescue ArgumentError
        raise Invalid, %(slots #{field} must be a year from #{YEARS.first} to #{YEARS.last}, or "#{word}")
      end
      private_class_method :parse_year

      def self.errors(settings)
        first = settings.first_year
        return [] if first.nil?

        last = settings.last_year
        if last && first > last
          [ "slots first_year must not come after last_year" ]
        elsif last.nil? && first > Challenges.today.year
          [ "slots first_year must not come after the current year" ]
        else
          []
        end
      end

      def self.apply!(challenge, settings)
        challenge.update_columns(slots_first_year: settings.first_year, slots_last_year: settings.last_year)
      end

      def self.rules(settings) = settings.to_h

      def self.as_json(_challenge, settings, **)
        { first_year: settings.first_year || BIRTH_YEAR, last_year: settings.last_year || CURRENT_YEAR }
      end

      # Starting a Run (Challenges::Runs.start!): the Run copies its first
      # year, the fixed one or the member's birth year, and keeps it even if
      # the Birth Date changes later. A birth-year Run needs the Birth Date.
      def self.run_attributes(challenge, user_id, today:)
        settings = load(challenge)
        return { first_year: settings.first_year } unless settings.birth_year?

        birth_date = RpgClubUser.where(user_id: user_id).pick(:birth_date)
        raise RunRefused.new("birth_date_required", BIRTH_DATE_REQUIRED) unless birth_date

        last_year = settings.last_year || today.year
        if birth_date.year > last_year
          raise RunRefused.new("no_slots", format(NO_SLOTS, last_year: last_year), status: :unprocessable_content)
        end

        { first_year: birth_date.year }
      end

      BIRTH_DATE_REQUIRED = "This Challenge starts at your birth year, so it needs your Birth Date. " \
                            "Other members will see your birth year on your Run, never the full date."
      NO_SLOTS = "This Challenge ends in %<last_year>d, before your birth year, so it has no slots for you."

      # What the member is told when their Run starts.
      def self.notices(run)
        return [] unless load(run.challenge).birth_year?

        [ { code: "birth_year_shown",
            message: "Other members will see your birth year, #{run.first_year}, on this Run." } ]
      end

      # The Run's years so far: from its first year to its last, or to the
      # current year for a range that grows.
      def self.years(run, today = Challenges.today)
        return (0...0) unless run.first_year

        run.first_year..(run.challenge.slots_last_year || today.year)
      end

      # Run progress (Challenges::Progress). A Cleared game fits the years it
      # was released in (Challenges::ReleaseYears) and fills at most one slot:
      #
      # - A game keeps the slot it has while it is still Cleared, still fits
      #   it and the year is still the Run's (a Finished Run keeps its slots
      #   whatever happens).
      # - Every other Cleared game, in the order they were Cleared, fills the
      #   earliest open slot it fits. One that fits no open slot stays on the
      #   Run without a slot, ready to fill one that opens.
      # - In Progress games are listed without a slot.
      #
      # Games that fit none of the Run's years are not counted.
      def self.count(run, plays)
        years = years(run)
        cleared = plays.cleared.dup
        stored = run.entries.select(&:cleared?)
        stored.each { |entry| cleared[entry.game_id] ||= counted_from(entry) } if run.finished?
        fits = ReleaseYears.of(cleared.keys | plays.in_progress)
          .transform_values { |list| list.select { |year| years.cover?(year) } }

        slots = {}
        stored.select(&:slot_year).each do |entry|
          game = cleared[entry.game_id]
          next unless game && !slots.key?(entry.slot_year)
          next unless run.finished? || fits[entry.game_id].include?(entry.slot_year)

          slots[entry.slot_year] = game.with(slot_year: entry.slot_year, picked_by_hand: entry.picked_by_hand)
        end
        slotted = slots.values.to_h { |game| [ game.game_id, game ] }

        filled = cleared.values.sort_by { |game| [ game.cleared_on, game.completion_id || 0, game.game_id ] }
          .filter_map do |game|
            next slotted[game.game_id] if slotted.key?(game.game_id)
            next unless fits[game.game_id].any? || run.finished?

            year = fits[game.game_id].find { |fit| !slots.key?(fit) }
            next game unless year

            slots[year] = game.with(slot_year: year)
          end
        filled + plays.in_progress.select { |id| fits[id].any? }.map { |id| Counted.in_progress(id) }
      end

      def self.counted_from(entry)
        Counted.cleared(entry.game_id, entry.completion_id, entry.cleared_on)
          .with(slot_year: entry.slot_year, picked_by_hand: entry.picked_by_hand)
      end
      private_class_method :counted_from

      # `cleared` is the slots filled so far, against `target`, the Run's
      # slots so far. A fixed range is Finished when every slot is Cleared; a
      # range that grows never Finishes, and is Caught Up while every slot so
      # far is Cleared and the Run is Active.
      def self.summary(run, entries)
        years = years(run)
        filled = entries.count { |entry| entry.slot_year && years.cover?(entry.slot_year) }
        target = years.count
        complete = target.positive? && filled >= target
        growing = run.challenge.slots_last_year.nil?
        Progress::Summary.new(in_progress: entries.count { |entry| entry.state == "in_progress" }, cleared: filled,
          target: target, goal_reached: complete && !growing, caught_up: complete && growing && run.active?)
      end

      # A slot move: the member puts a Cleared game of their Run in another
      # open year it fits (Challenges::Runs.move!). The game keeps that slot
      # while it still holds, and its old slot is free for other games.
      # Raises Challenges::RunRefused.
      def self.move!(run, game_id, year)
        entry = run.entries.find { |row| row.game_id == game_id && row.cleared? }
        raise RunRefused.new("not_cleared", NOT_CLEARED, status: :unprocessable_content) unless entry
        return if entry.slot_year == year

        years = years(run)
        unless years.cover?(year)
          raise RunRefused.new("slot_out_of_range", format(OUT_OF_RANGE, year: year, first: years.first, last: years.last),
            status: :unprocessable_content)
        end
        unless ReleaseYears.of([ game_id ]).fetch(game_id).include?(year)
          raise RunRefused.new("slot_not_fitting", format(NOT_FITTING, title: title_of(game_id), year: year),
            status: :unprocessable_content)
        end
        holder = run.entries.find { |row| row.slot_year == year }
        if holder
          raise RunRefused.new("slot_filled", format(FILLED, year: year, title: title_of(holder.game_id)),
            game_id: holder.game_id)
        end

        entry.update!(slot_year: year, picked_by_hand: true)
      end

      def self.title_of(game_id) = GamedbGame.where(game_id: game_id).pick(:title)
      private_class_method :title_of

      NOT_CLEARED = "Only a game Cleared on this Run can fill a slot."
      OUT_OF_RANGE = "%<year>d is not one of this Run's years (%<first>d to %<last>d)."
      NOT_FITTING = "%<title>s wasn't released in %<year>d, so it can't fill that year."
      FILLED = "%<year>d is already filled by %<title>s."

      # The Run's slots as the API serves them: each year so far with the
      # game filling it (null while open).
      def self.run_json(run)
        years = years(run)
        by_year = run.entries.select(&:slot_year).index_by(&:slot_year)
        { first_year: run.first_year, last_year: run.first_year && years.last, growing: run.challenge.slots_last_year.nil?,
          years: years.map do |year|
            entry = by_year[year]
            { year: year, game_id: entry&.game_id, title: entry&.game&.title }
          end }
      end
    end
  end
end
