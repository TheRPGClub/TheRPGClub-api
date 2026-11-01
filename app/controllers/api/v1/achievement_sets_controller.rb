# frozen_string_literal: true

module Api
  module V1
    # Achievement Sets (ADR 0001). `update` is the admin-only manual fix for a
    # set's GameDB link, which Achievements::LinkSetToGame resolves
    # best-effort and never overwrites.
    class AchievementSetsController < ApplicationController
      before_action :require_admin!, only: %i[update]

      # PATCH /api/v1/achievement_sets/:id
      # Body: { "data": { "game_id": <gamedb_games.game_id | null> } }
      def update
        set = AchievementSet.find(params[:id])
        data = request_data
        raise ActionController::ParameterMissing, "game_id" unless data.key?("game_id")

        game_id = data["game_id"].presence
        if game_id && !GamedbGame.exists?(game_id:)
          return render json: { error: "game not found" }, status: :unprocessable_entity
        end

        set.update!(game_id:)
        render json: { data: AchievementSetLinkResource.new(set).serializable_hash }
      end

      private

      # Admins only: a role_admin member or a dev. The service token is
      # refused, since links are a human judgement.
      def require_admin!
        return true if current_principal&.discord_user? &&
          (current_principal.dev? || RpgClubUser.where(user_id: current_principal.id, role_admin: true).exists?)

        render json: { error: "forbidden" }, status: :forbidden
        false
      end
    end
  end
end
