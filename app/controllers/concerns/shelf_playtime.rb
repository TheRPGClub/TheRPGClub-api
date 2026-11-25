# frozen_string_literal: true

# Playtime on a member's shelf lists (spec api#457, ticket api#460): Now
# Playing, Game Completions, Backlog, Favorites and Collection. Each item gets
# `playtime_minutes` (ShelfPlaytimeFields) from one Playtime::Ledger read, so
# there are no per-item queries.
#
# `sort=most_played` orders by the member's Playtime for the game (most
# first, none counting as 0), then title, then the entry id. With no `sort`
# the list keeps its own order; any other value is 422 `invalid_sort`.
module ShelfPlaytime
  extend ActiveSupport::Concern

  SORTS = %w[most_played].freeze

  private

  # render_collection for the member's (`params[:user_id]`) shelf `scope`,
  # with each item's Playtime and the `sort` param applied.
  def render_shelf(scope, resource:, default_order:)
    user_id = params[:user_id].to_s
    sort = params[:sort].presence
    return render_invalid_shelf_sort if sort && SORTS.exclude?(sort)

    if sort == "most_played"
      ledger = Playtime::Ledger.new(user_ids: [ user_id ])
      order = most_played_order(scope.model, ledger.minutes_by_game(user_id))
      return render_collection(scope, resource:, default_order: order, params: { shelf_playtime: ledger })
    end

    render_collection(scope, resource:, default_order:, prepare: lambda { |records|
      { shelf_playtime: Playtime::Ledger.new(user_ids: [ user_id ], game_ids: records.filter_map(&:gamedb_game_id).uniq) }
    })
  end

  # Playtime (from `minutes`, { game_id => minutes }) descending, then the
  # game's title, then the entry id. The figures go in as bound arrays
  # (empty ones read as one NULL row, so every game counts as 0).
  def most_played_order(model, minutes)
    table = model.table_name
    played = model.sanitize_sql_array([ <<~SQL.squish, minutes.keys, minutes.values ])
      COALESCE((SELECT v.minutes FROM unnest(ARRAY[?]::bigint[], ARRAY[?]::bigint[]) AS v(game_id, minutes)
      WHERE v.game_id = #{table}.gamedb_game_id), 0) DESC
    SQL
    Arel.sql("#{played}, (SELECT LOWER(g.title) FROM gamedb_games g WHERE g.game_id = #{table}.gamedb_game_id) " \
             "ASC NULLS LAST, #{table}.#{model.primary_key} ASC")
  end

  def render_invalid_shelf_sort
    render json: { error: "invalid_sort", message: "sort must be one of: #{SORTS.join(', ')}" },
      status: :unprocessable_content
  end
end
