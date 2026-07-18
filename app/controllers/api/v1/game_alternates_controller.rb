# frozen_string_literal: true

module Api
  module V1
    # Alternate-version links between two games (gamedb_game_alternates), the
    # bot's `linkAlternateVersions`. Admin/service-only.
    class GameAlternatesController < ApplicationController
      before_action :require_admin_or_service!, only: %i[create]

      # POST /api/v1/games/:id/alternates  { data: { alt_game_id } }
      #
      # Links the path game and `alt_game_id` as alternate versions of each
      # other. The pair is stored once, ordered low id first to satisfy the
      # table's `game_id < alt_game_id` CHECK constraint, so the link is
      # symmetric regardless of which game the request hangs off. Idempotent
      # (ON CONFLICT DO NOTHING): re-linking returns the existing link with 200.
      # Returns the game's full alternates list (same shape as the `alternates`
      # slice of GET /api/v1/games/:id/relations).
      def create
        game = GamedbGame.find(params[:id])
        alt_id = alt_game_id
        return render(json: { error: "a game cannot be its own alternate" }, status: :unprocessable_entity) if alt_id == game.game_id

        low, high = [ game.game_id, alt_id ].minmax
        link = GamedbGameAlternate
          .create_with(created_by: current_principal&.id)
          .find_or_create_by!(game_id: low, alt_game_id: high)

        if link.previously_new_record?
          # Bump updated_at on both linked games so GamesController#relations_data's
          # cache (keyed on it) picks up the new alternate on either side.
          game.touch
          GamedbGame.find(alt_id).touch
        end

        render json: { data: GameResource.new(game.alternate_games).serializable_hash },
          status: link.previously_new_record? ? :created : :ok
      end

      private

      # The other game to link, from `{ data: { alt_game_id } }`. A missing or
      # non-integer value is a 400 (ParameterMissing -> render_bad_request); a
      # non-existent id surfaces as a 422 foreign-key error on insert.
      def alt_game_id
        raw = params.dig(:data, :alt_game_id).presence
        raise ActionController::ParameterMissing, :alt_game_id if raw.blank?

        Integer(raw)
      rescue ArgumentError, TypeError
        raise ActionController::ParameterMissing, :alt_game_id
      end
    end
  end
end
