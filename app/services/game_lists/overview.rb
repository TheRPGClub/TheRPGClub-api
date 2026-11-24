# frozen_string_literal: true

module GameLists
  # What a page of Game Lists shows besides the lists themselves, read for
  # the whole page at once: each list's entry count and its first games in
  # its own order (for the card's covers).
  module Overview
    PREVIEW_MAX = 4

    # Each list's own sort (GameLists.entry_order) inside one window.
    WINDOW_ORDER = "CASE WHEN game_lists.sort = 'alphabetical' THEN lower(gamedb_games.title) END ASC, " \
                   "CASE WHEN game_lists.sort = 'added' THEN game_list_entries.added_at END DESC, " \
                   "CASE WHEN game_lists.sort = 'added' THEN -game_list_entries.position END ASC, " \
                   "game_list_entries.position ASC"
    PLACED = "game_list_entries.game_list_id, game_list_entries.game_id, " \
             "row_number() OVER (PARTITION BY game_list_entries.game_list_id ORDER BY #{WINDOW_ORDER}) AS place"

    module_function

    # { counts: { list_id => count }, previews: { list_id => [game, ...] } }
    def of(lists)
      ids = lists.map(&:id)
      return { counts: {}, previews: {} } if ids.empty?

      { counts: GameListEntry.where(game_list_id: ids).group(:game_list_id).count, previews: previews(ids) }
    end

    def previews(ids)
      ranked = GameListEntry.joins(:game, :game_list).where(game_list_id: ids).select(PLACED)
      rows = GameListEntry.from(ranked, :game_list_entries).where("place <= ?", PREVIEW_MAX).order(:game_list_id, :place)
        .pluck(:game_list_id, :game_id)
      games = GamedbGame.where(game_id: rows.map(&:last).uniq).preload(:images).index_by(&:game_id)
      rows.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(list_id, game_id), previews|
        game = games[game_id]
        previews[list_id] << { game_id: game.game_id, title: game.title, cover_url: game.cover_url } if game
      end
    end

    private_class_method :previews
  end
end
