# frozen_string_literal: true

# The optional `game_id` list filter (exact `gamedb_game_id`) on a member's
# Backlog, Favorites, Game Completions and Collection. A value that isn't an
# integer matches nothing (an empty list), rather than `IS NULL`, which would
# match Backlog rows with no game.
module GameIdFilter
  extend ActiveSupport::Concern

  private

  def by_game(scope)
    return scope if params[:game_id].blank?

    game_id = Integer(params[:game_id].to_s, 10, exception: false)
    game_id ? scope.where(gamedb_game_id: game_id) : scope.none
  end
end
