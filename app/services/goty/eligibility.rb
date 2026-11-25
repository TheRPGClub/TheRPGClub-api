# frozen_string_literal: true

module Goty
  # Whether a game may be nominated for year Y's Game of the Year (GLOSSARY
  # "Game of the Year"; spec api#471). A game is eligible when its earliest
  # dated Release (IGDB or Manual, any region or platform) falls in Y; a vague
  # date counts by its stored start, so a Release known only to the year
  # counts for that year. A game with no dated Release falls back to its
  # `initial_release_date`, and with neither it is `release_unknown`.
  #
  # Every GameDB game stands alone: an Alternate Version (a remake, a
  # remaster) is judged by its own Releases, never its original's.
  module Eligibility
    REASONS = %w[not_released_in_year release_unknown].freeze

    # `released_on` is the date judged (nil when unknown), `date_precision`
    # its Date Precision ("day" for the initial release date), and `source`
    # where it came from: "release" or "initial_release_date".
    Result = Data.define(:game_id, :year, :released_on, :date_precision, :source, :reason) do
      def eligible? = reason.nil?
    end

    module_function

    def check(game_or_id, year)
      game_id = game_or_id.is_a?(GamedbGame) ? game_or_id.game_id : Integer(game_or_id)
      check_all([ game_id ], year).fetch(game_id)
    end

    # { game_id => Result } for several games in two queries.
    def check_all(game_ids, year)
      year = Integer(year)
      ids = game_ids.map { |id| Integer(id) }.uniq
      earliest = earliest_releases(ids)
      initial = GamedbGame.where(game_id: ids - earliest.keys).where.not(initial_release_date: nil)
        .pluck(:game_id, :initial_release_date).to_h

      ids.index_with do |id|
        released_on, precision, source =
          if (row = earliest[id]) then [ row.first, row.last, "release" ]
          elsif (at = initial[id]) then [ at.utc.to_date, "day", "initial_release_date" ]
          end
        Result.new(game_id: id, year: year, released_on: released_on, date_precision: precision, source: source,
          reason: reason_for(released_on, year))
      end
    end

    def reason_for(released_on, year)
      return "release_unknown" if released_on.nil?

      "not_released_in_year" unless released_on.year == year
    end

    # { game_id => [release_date, date_precision] } of each game's earliest
    # dated Release; on one date the more precise Release is reported.
    def earliest_releases(ids)
      GamedbRelease.where(game_id: ids).where.not(release_date: nil)
        .pluck(:game_id, :release_date, :date_precision)
        .group_by(&:first)
        .transform_values do |rows|
          rows.min_by { |_, date, precision| [ date, GamedbRelease.precision_rank(precision) ] }.drop(1)
        end
    end
  end
end
