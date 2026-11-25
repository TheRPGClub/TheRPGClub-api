# frozen_string_literal: true

module Gotm
  # GOTM / NR-GOTM history grouped by round, the server-side twin of the bot's
  # `/gotm history` (round-history.command.ts) and `/gotm current`.
  #
  # Filters apply per kind to a round's whole block, as in the bot: `year`
  # matches the trailing four-digit year of `month_year`, and `query` keeps a
  # kind's block for a round when any of its winners' or that kind's
  # Nominations' titles match, with all of that block's winners. The block
  # then lists the matching games as `matches` (`won` or `nominated`).
  # NR-GOTM "N/A" placeholder games are dropped from the games list, but the
  # round still counts.
  class RoundHistory
    KINDS = { "gotm" => GotmEntry, "nr_gotm" => NrGotmEntry }.freeze
    NOMINATIONS = { "gotm" => GotmNomination, "nr_gotm" => NrGotmNomination }.freeze
    KIND_PARAMS = (KINDS.keys + [ "both" ]).freeze
    SORTS = %w[asc desc].freeze
    YEAR_SQL = "SUBSTRING(month_year FROM '(\\d{4})\\s*$')::int"
    PLACEHOLDER_TITLE = "n/a"

    # The round number of the latest GOTM round (bot `Gotm.getLatestRound`),
    # or nil when there are no GOTM entries.
    def self.latest_round_number
      GotmEntry.maximum(:round_number)
    end

    def initialize(kind: "both", year: nil, query: nil)
      @kinds = kind == "both" ? KINDS.keys : [ kind ]
      @year = year
      @query = query.presence
    end

    # One row per matching round number (selected as `round_number`), ordered
    # by round. Grouped, so callers pass `round_count` to Pagy explicitly.
    def rounds_relation(sort: "desc")
      GotmEntry.unscoped
        .from(round_numbers_source)
        .select("gotm_rounds.round_number")
        .order(Arel.sql("gotm_rounds.round_number #{sort == 'asc' ? 'ASC' : 'DESC'}"))
    end

    def round_count
      GotmEntry.unscoped.from(round_numbers_source).count
    end

    # Every year present across the selected kinds, newest first, ignoring
    # the year and query filters (they are the options for the year filter).
    def years
      @kinds.flat_map { |kind| KINDS.fetch(kind).distinct.pluck(Arel.sql(YEAR_SQL)) }.compact.uniq.sort.reverse
    end

    # The serialized rounds for `round_numbers`, in the given order.
    def rounds(round_numbers)
      blocks = @kinds.index_with { |kind| entries_by_round(kind, round_numbers) }
      thread_ids = first_thread_ids(blocks.values.flat_map(&:values).flatten.filter_map(&:gamedb_game_id))
      nomination_counts = @kinds.index_with { |kind| nomination_counts(kind, round_numbers) }
      matches = @query ? @kinds.index_with { |kind| title_matches(kind, round_numbers) } : {}

      round_numbers.map do |number|
        round = { round_number: number }
        KINDS.each_key do |kind|
          entries = blocks.dig(kind, number)
          round[kind.to_sym] = entries && serialize_block(kind, entries, thread_ids).merge(
            nominations_count: nomination_counts.dig(kind, number) || 0,
            matches: matches[kind] && serialize_matches(kind, number, entries, matches[kind])
          )
        end
        round
      end
    end

    # The winning entries of `round_numbers`, flattened in round order, GOTM
    # before NR-GOTM, `game_index` order within a kind, as `[kind, entry]`
    # pairs. Drops the NR-GOTM "N/A" placeholders and entries without a game.
    # Only the games' images are preloaded (no platforms or threads).
    def winners(round_numbers)
      blocks = @kinds.index_with { |kind| entries_by_round(kind, round_numbers, preload: { game: :images }) }

      round_numbers.flat_map do |number|
        @kinds.flat_map do |kind|
          Array(blocks.dig(kind, number))
            .reject { |entry| entry.game.nil? || (kind == "nr_gotm" && placeholder?(entry)) }
            .map { |entry| [ kind, entry ] }
        end
      end
    end

    private

    # `(SELECT DISTINCT round_number ... UNION SELECT DISTINCT round_number ...)
    # gotm_rounds` over the selected kinds' filtered entries: one row per
    # round. The DISTINCT matters for a single kind, where there is no UNION
    # to dedupe and a round with co-winners would otherwise appear once per
    # entry, inflating the count and repeating rounds across pages.
    def round_numbers_source
      selects = @kinds.map { |kind| filtered_scope(kind).select(:round_number).distinct.arel }
      union = selects.reduce { |left, right| Arel::Nodes::Union.new(left, right) }
      Arel::Nodes::TableAlias.new(Arel::Nodes::Grouping.new(union), "gotm_rounds")
    end

    def filtered_scope(kind)
      model = KINDS.fetch(kind)
      scope = model.all
      scope = scope.where("#{YEAR_SQL} = ?", @year) if @year
      if @query
        scope = scope.where(round_number: title_matching(model).select(:round_number))
          .or(scope.where(round_number: title_matching(NOMINATIONS.fetch(kind)).select(:round_number)))
      end
      scope
    end

    # `model`'s rows (winners or Nominations) whose game title matches `query`.
    def title_matching(model)
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(Gamedb::TitleArticle.strip(@query))}%"
      model.joins(:game).where("gamedb_games.title ILIKE ?", pattern)
    end

    def nomination_counts(kind, round_numbers)
      NOMINATIONS.fetch(kind).where(round_number: round_numbers).group(:round_number).count
    end

    # The page's title-matching games of `kind`: the winners as a Set of
    # `[round_number, game_id]`, and the Nominations as
    # `{ round_number => [[game_id, title], ...] }` in nomination order.
    def title_matches(kind, round_numbers)
      won = title_matching(KINDS.fetch(kind)).where(round_number: round_numbers)
        .pluck(:round_number, :gamedb_game_id).to_set
      nominated = title_matching(NOMINATIONS.fetch(kind)).where(round_number: round_numbers)
        .order(:round_number, :nominated_at, :nomination_id)
        .pluck(:round_number, "gamedb_games.game_id", "gamedb_games.title")
        .group_by(&:first).transform_values { |rows| rows.map { |row| row.drop(1) } }
      [ won, nominated ]
    end

    # Matching winners first (`game_index` order), then matching Nominations
    # that did not win; one entry per game.
    def serialize_matches(kind, number, entries, (won, nominated))
      winners = entries.reject { |entry| entry.game.nil? || (kind == "nr_gotm" && placeholder?(entry)) }
        .select { |entry| won.include?([ number, entry.gamedb_game_id ]) }
        .map { |entry| { gamedb_game_id: entry.gamedb_game_id, title: entry.game.title, match: "won" } }
      others = nominated.fetch(number, []).map { |id, title| { gamedb_game_id: id, title:, match: "nominated" } }
      (winners + others).uniq { |match| match[:gamedb_game_id] }
    end

    def entries_by_round(kind, round_numbers, preload: { game: [ :images, :platforms ] })
      filtered_scope(kind)
        .where(round_number: round_numbers)
        .preload(preload)
        .order(:round_number, :game_index)
        .group_by(&:round_number)
    end

    def serialize_block(kind, entries, thread_ids)
      games = entries.reject { |entry| kind == "nr_gotm" && placeholder?(entry) }
      {
        month_year: entries.first.month_year,
        voting_results_message_id: entries.filter_map(&:voting_results_message_id).first,
        games: games.map { |entry| serialize_game(entry, thread_ids) }
      }
    end

    def serialize_game(entry, thread_ids)
      {
        game_index: entry.game_index,
        gamedb_game_id: entry.gamedb_game_id,
        reddit_url: entry.reddit_url,
        thread_id: thread_ids[entry.gamedb_game_id],
        game: entry.game && GameWithPlatformsResource.new(entry.game).serializable_hash
      }
    end

    def placeholder?(entry)
      entry.game&.title.to_s.strip.casecmp?(PLACEHOLDER_TITLE)
    end

    # Each game's newest linked thread, the bot's `GET /games/:id/threads`
    # `data[0]` (ThreadsController#game_index orders `created_at desc`).
    def first_thread_ids(game_ids)
      return {} if game_ids.empty?

      ThreadGameLink.joins(:thread)
        .where(gamedb_game_id: game_ids.uniq)
        .select("DISTINCT ON (thread_game_links.gamedb_game_id) thread_game_links.gamedb_game_id, " \
                "thread_game_links.thread_id")
        .order("thread_game_links.gamedb_game_id, threads.created_at DESC")
        .to_h { |link| [ link.gamedb_game_id, link.thread_id ] }
    end
  end
end
