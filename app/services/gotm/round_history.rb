# frozen_string_literal: true

module Gotm
  # GOTM / NR-GOTM history grouped by round, the server-side twin of the bot's
  # `/gotm history` (round-history.command.ts) and `/gotm current`.
  #
  # Filters apply per kind to a round's whole block, as in the bot: `year`
  # matches the trailing four-digit year of `month_year`, and `query` keeps a
  # kind's block for a round when any of its games' titles match, with all of
  # that block's games. NR-GOTM "N/A" placeholder games are dropped from the
  # games list, but the round still counts.
  class RoundHistory
    KINDS = { "gotm" => GotmEntry, "nr_gotm" => NrGotmEntry }.freeze
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

      round_numbers.map do |number|
        round = { round_number: number }
        KINDS.each_key do |kind|
          entries = blocks.dig(kind, number)
          round[kind.to_sym] = entries && serialize_block(kind, entries, thread_ids)
        end
        round
      end
    end

    private

    # `(SELECT round_number ... UNION SELECT round_number ...) gotm_rounds`
    # over the selected kinds' filtered entries.
    def round_numbers_source
      selects = @kinds.map { |kind| filtered_scope(kind).select(:round_number).arel }
      union = selects.reduce { |left, right| Arel::Nodes::Union.new(left, right) }
      Arel::Nodes::TableAlias.new(Arel::Nodes::Grouping.new(union), "gotm_rounds")
    end

    def filtered_scope(kind)
      model = KINDS.fetch(kind)
      scope = model.all
      scope = scope.where("#{YEAR_SQL} = ?", @year) if @year
      if @query
        matching = model.joins(:game)
          .where("gamedb_games.title ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(@query.strip)}%")
          .select(:round_number)
        scope = scope.where(round_number: matching)
      end
      scope
    end

    def entries_by_round(kind, round_numbers)
      filtered_scope(kind)
        .where(round_number: round_numbers)
        .preload(game: [ :images, :platforms ])
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
