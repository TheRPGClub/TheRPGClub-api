# frozen_string_literal: true

module Gamedb
  # The Release Calendar's entries (spec #389, ticket #394; GLOSSARY.md
  # "Release Calendar", "Upcoming Release").
  #
  # An Upcoming Release is one game's Releases that share a date and Date
  # Precision, across platforms and regions (Japan included). Each one is
  # placed on the calendar by its Date Precision:
  #
  # - a `month` Release before day 1 of its month;
  # - a `day` Release on its date;
  # - a `quarter` Release after the last day of its quarter's last month;
  # - a `year` Release after 31 December of its year, after that year's Q4;
  # - a `tba` Release after everything.
  #
  # Ties break on game title, then game id.
  #
  # Without a `month` the window runs from `today` forward with no end: a
  # `day` Release counts on and after its date, a vague one until its whole
  # period has ended, a `tba` one always. With a `month` (the first day of a
  # calendar month) the window is the Upcoming Releases placed in that month,
  # past or future: its days, the month itself, a quarter ending in it and,
  # for December, the year. TBA is never in a month.
  class UpcomingReleases
    Entry = Data.define(:game, :date, :date_precision, :releases, :first_released) do
      # The game's earliest dated Release, when it comes before this entry
      # (always, for a TBA entry); otherwise nil.
      def first_released_before
        return nil if first_released.nil?
        return first_released if date.nil? || first_released.date < date

        nil
      end

      # The heading a client renders the entry under: the month for `day` and
      # `month` entries, "Q3 2027", "2027" or "TBA".
      def section
        case date_precision
        when "tba" then "TBA"
        when "year" then date.year.to_s
        when "quarter" then "Q#{((date.month - 1) / 3) + 1} #{date.year}"
        else date.strftime("%B %Y")
        end
      end
    end

    # A game's earliest dated Release: its date and Date Precision.
    FirstRelease = Data.define(:date, :date_precision)

    # The order of each Date Precision among entries placed on the same day.
    PLACEMENT_SQL = <<~SQL.squish
      CASE e.date_precision
        WHEN 'month' THEN 0 WHEN 'day' THEN 1 WHEN 'quarter' THEN 2 WHEN 'year' THEN 3 ELSE 4
      END
    SQL

    # The day an entry is placed on: a quarter or year on its last day, a
    # month or day on its stored date, TBA on none.
    PLACED_ON_SQL = <<~SQL.squish
      CASE WHEN e.date_precision IN ('quarter', 'year') THEN #{GamedbRelease.period_ends_on_sql('e')}
        ELSE e.release_date
      END
    SQL

    # The last day an entry is still upcoming on.
    PERIOD_ENDS_ON_SQL = GamedbRelease.period_ends_on_sql("e")

    def initialize(today:, month: nil, platform_ids: [], game_ids: [], next_per_game: false)
      @today = today
      @month = month
      @platform_ids = platform_ids
      @game_ids = game_ids
      @next_per_game = next_per_game
    end

    # [total entry count, the page's Entries in calendar order].
    def page(page:, limit:)
      rows = select_rows(page_sql(page: page, limit: limit))
      count = rows.first&.fetch("entries_count") || (page > 1 ? total : 0)
      [ count.to_i, entries(rows) ]
    end

    private

    # The entry count, for a page past the end (which has no rows to carry it).
    def total
      GamedbRelease.connection.select_value("SELECT COUNT(*) FROM (#{chosen_sql}) chosen")
    end

    def select_rows(sql)
      GamedbRelease.connection.select_all(sql).to_a
    end

    def sanitize(*args)
      GamedbRelease.sanitize_sql_array(args)
    end

    def page_sql(page:, limit:)
      sanitize(<<~SQL.squish, limit: limit, offset: limit * (page - 1))
        SELECT c.game_id, c.release_date, c.date_precision, COUNT(*) OVER () AS entries_count
        FROM (#{chosen_sql}) c
        ORDER BY c.placed_on ASC NULLS LAST, c.placement, c.title, c.game_id
        LIMIT :limit OFFSET :offset
      SQL
    end

    # The window's entries, each with its placement, the game's title, and
    # (with `next_per_game`) only each game's earliest one.
    def chosen_sql
      windowed = <<~SQL.squish
        SELECT e.game_id, e.release_date, e.date_precision, g.title,
          #{PLACED_ON_SQL} AS placed_on, #{PLACEMENT_SQL} AS placement
        FROM (#{grouped_sql}) e
        JOIN gamedb_games g ON g.game_id = e.game_id
        WHERE #{window_sql}
      SQL
      return windowed unless @next_per_game

      <<~SQL.squish
        SELECT w.* FROM (
          SELECT w.*, ROW_NUMBER() OVER (
            PARTITION BY w.game_id ORDER BY w.placed_on ASC NULLS LAST, w.placement
          ) AS game_rank
          FROM (#{windowed}) w
        ) w
        WHERE w.game_rank = 1
      SQL
    end

    # One row per game, date and Date Precision: the Upcoming Releases. With
    # platform ids, only those with a Release on one of them.
    def grouped_sql
      conditions = []
      conditions << sanitize("r.game_id IN (:ids)", ids: @game_ids) if @game_ids.any?
      having = @platform_ids.any? ? sanitize("HAVING bool_or(r.platform_id IN (:ids))", ids: @platform_ids) : ""

      <<~SQL.squish
        SELECT r.game_id, r.release_date, r.date_precision
        FROM gamedb_releases r
        #{conditions.any? ? "WHERE #{conditions.join(' AND ')}" : ''}
        GROUP BY r.game_id, r.release_date, r.date_precision
        #{having}
      SQL
    end

    def window_sql
      if @month
        sanitize("(#{PLACED_ON_SQL}) BETWEEN :from AND :to", from: @month, to: @month.end_of_month)
      else
        sanitize("(e.date_precision = 'tba' OR (#{PERIOD_ENDS_ON_SQL}) >= :today)", today: @today)
      end
    end

    def entries(rows)
      return [] if rows.empty?

      game_ids = rows.map { |row| row.fetch("game_id") }.uniq
      games = GamedbGame.where(game_id: game_ids).preload(:images).index_by(&:game_id)
      releases = GamedbRelease.where(game_id: game_ids).includes(:platform, :region).to_a
        .group_by { |release| [ release.game_id, release.release_date, release.date_precision ] }
      firsts = first_releases(game_ids)

      rows.map do |row|
        key = [ row.fetch("game_id"), row["release_date"] && Date.parse(row["release_date"].to_s), row.fetch("date_precision") ]
        Entry.new(
          game: games.fetch(key[0]), date: key[1], date_precision: key[2],
          releases: releases.fetch(key, []).sort_by { |r| [ r.platform.platform_name, r.region.region_name, r.release_id ] },
          first_released: firsts[key[0]]
        )
      end
    end

    # Each game's earliest dated Release: the earliest stored date, the more
    # precise Date Precision on a tie.
    def first_releases(game_ids)
      GamedbRelease.where(game_id: game_ids).where.not(release_date: nil)
        .select("DISTINCT ON (game_id) game_id, release_date, date_precision")
        .order(Arel.sql("game_id, release_date, #{GamedbRelease.precision_rank_sql("gamedb_releases")}"))
        .to_h { |release| [ release.game_id, FirstRelease.new(date: release.release_date, date_precision: release.date_precision) ] }
    end
  end
end
