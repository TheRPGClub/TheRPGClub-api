# frozen_string_literal: true

module Completions
  # The games two members have both completed (the bot's `/game-completion
  # common`, `completion-common.service.ts`), computed in SQL rather than by
  # diffing both members' full histories.
  #
  # A game is "common" when both members have at least one completion of it.
  # Filters follow the bot's semantics: a game matches when ANY of either
  # member's entries for it match (`BOOL_OR` over the grouped rows), so e.g.
  # `year=2020` keeps a game the left member finished in 2020 even if the right
  # member finished it later.
  #
  # - `year`         completion year, or the literal `unknown` for any undated entry
  # - `platform_id`  any entry on that platform
  # - `q`            case-insensitive game-title substring
  # - `sort`         `date_desc` (default) / `date_asc` order by the latest
  #                  completion date across both members (undated games last,
  #                  ties by title); `title_asc` / `title_desc` order by title.
  #                  Unlike the bot, which always renders `title_asc`, the sort
  #                  is honoured.
  #
  # `relation` is a grouped relation (one row per game, `latest_shared_date`
  # selected), paired with an explicit `count` for pagy. `rows` turns a page of
  # it into Row values carrying each side's latest entry and completion count.
  class Common
    SORTS = %w[date_desc date_asc title_desc title_asc].freeze
    DEFAULT_SORT = "date_desc"

    Side = Data.define(:latest, :count)
    Row = Data.define(:gamedb_game_id, :game, :latest_shared_date, :left, :right)

    class InvalidSort < ArgumentError; end

    TITLE_ORDER = "LOWER(gamedb_games.title) %s, gamedb_games.game_id ASC"
    DATE_ORDER = "MAX(user_game_completions.completed_at) %s NULLS LAST, LOWER(gamedb_games.title) ASC, gamedb_games.game_id ASC"

    attr_reader :left_user_id, :right_user_id

    def initialize(left_user_id:, right_user_id:, year: nil, platform_id: nil, q: nil, sort: nil)
      @left_user_id = left_user_id.to_s
      @right_user_id = right_user_id.to_s
      @year = year.presence
      @platform_id = platform_id.presence
      @q = q.presence
      @sort = sort.presence || DEFAULT_SORT
      raise InvalidSort, "sort must be one of #{SORTS.join(', ')}" unless SORTS.include?(@sort)
    end

    # One row per common game, ordered per `sort`.
    def relation
      grouped
        .joins(:game)
        .group("gamedb_games.game_id")
        .select("user_game_completions.gamedb_game_id", "MAX(user_game_completions.completed_at) AS latest_shared_date")
        .order(Arel.sql(order_sql))
    end

    # The number of common games after filtering, for pagy.
    def count
      UserGameCompletion.from(grouped.select(:gamedb_game_id), :common_games).count
    end

    # Expand a page of `relation` into Rows: each side's latest entry (latest
    # `completed_at`, undated last, then highest `completion_id`) and count.
    def rows(page)
      game_ids = page.map(&:gamedb_game_id)
      entries = both_users.where(gamedb_game_id: game_ids)
        .preload(:game, :platform)
        .order(Arel.sql("completed_at DESC NULLS LAST, completion_id DESC"))
        .group_by { |entry| [ entry.gamedb_game_id, entry.user_id ] }

      page.map do |row|
        left = side(entries.fetch([ row.gamedb_game_id, left_user_id ]))
        Row.new(
          gamedb_game_id: row.gamedb_game_id,
          game: left.latest.game,
          latest_shared_date: row.latest_shared_date,
          left: left,
          right: side(entries.fetch([ row.gamedb_game_id, right_user_id ]))
        )
      end
    end

    private

    def side(entries) = Side.new(latest: entries.first, count: entries.size)

    def both_users
      UserGameCompletion.where(user_id: [ left_user_id, right_user_id ])
    end

    def grouped
      scope = both_users.group(:gamedb_game_id).having("COUNT(DISTINCT user_game_completions.user_id) = 2")

      if @q
        titles = GamedbGame.where("title ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(@q.to_s.strip)}%").select(:game_id)
        scope = scope.where(gamedb_game_id: titles)
      end

      if @year
        scope =
          if @year.to_s.casecmp?("unknown")
            scope.having("BOOL_OR(user_game_completions.completed_at IS NULL)")
          else
            scope.having("BOOL_OR(EXTRACT(YEAR FROM user_game_completions.completed_at) = ?)", @year.to_i)
          end
      end

      scope = scope.having("BOOL_OR(user_game_completions.platform_id = ?)", @platform_id.to_i) if @platform_id
      scope
    end

    def order_sql
      case @sort
      when "date_desc" then format(DATE_ORDER, "DESC")
      when "date_asc" then format(DATE_ORDER, "ASC")
      when "title_asc" then format(TITLE_ORDER, "ASC")
      when "title_desc" then format(TITLE_ORDER, "DESC")
      end
    end
  end
end
