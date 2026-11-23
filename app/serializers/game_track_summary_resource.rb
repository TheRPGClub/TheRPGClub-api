# frozen_string_literal: true

# An embedded game with the `gotm_won` / `nr_gotm_won` flags GameResource
# serves, for a game preloaded without the `without_images` aliases (the
# Review Feed). The caller passes the page's winning game ids as
# `params[:gotm_game_ids]` / `params[:nr_gotm_game_ids]` (see .params_for),
# so a page costs two queries rather than two per game.
class GameTrackSummaryResource
  include BaseResource
  include GameFields

  attribute(:gotm_won) { |game| params.fetch(:gotm_game_ids).include?(game.game_id) }
  attribute(:nr_gotm_won) { |game| params.fetch(:nr_gotm_game_ids).include?(game.game_id) }

  # The winning game ids among `game_ids`, as the params this resource reads.
  def self.params_for(game_ids)
    {
      gotm_game_ids: GotmEntry.where(gamedb_game_id: game_ids).distinct.pluck(:gamedb_game_id).to_set,
      nr_gotm_game_ids: NrGotmEntry.where(gamedb_game_id: game_ids).distinct.pluck(:gamedb_game_id).to_set
    }
  end
end
