# frozen_string_literal: true

module Api
  module V1
    # Steam app -> GameDB game mapping cache (#166), shared across every
    # user's Steam collection import so a repeated Steam app doesn't need to
    # be re-resolved by the bot's matcher. Bot-written; read is open to any
    # authenticated caller.
    class SteamAppGamedbMapsController < ApplicationController
      before_action :require_admin_or_service!, only: %i[create]

      # GET /api/v1/steam_app_gamedb_maps/:steam_app_id
      def show
        record = RpgClubSteamAppGamedbMap.find_by!(steam_app_id: params[:steam_app_id])
        render json: { data: SteamAppGamedbMapResource.new(record).serializable_hash }
      end

      # POST /api/v1/steam_app_gamedb_maps
      # Body: { "data": { steam_app_id, gamedb_game_id, status, created_by } }
      #
      # Upsert keyed on steam_app_id, mirroring JournalMessageContextsController#create.
      def create
        data = request_data
        steam_app_id = data["steam_app_id"].presence
        raise ActionController::ParameterMissing, "steam_app_id" if steam_app_id.nil?

        record = RpgClubSteamAppGamedbMap.find_or_initialize_by(steam_app_id: steam_app_id)
        created = record.new_record?
        record.assign_attributes(data)
        record.save!

        render json: { data: SteamAppGamedbMapResource.new(record).serializable_hash },
          status: created ? :created : :ok
      end

      # GET /api/v1/users/:user_id/steam_app_gamedb_maps/historical
      #
      # The distinct gamedb_game_ids this user has previously mapped a Steam
      # app to, so the bot can bias fuzzy matching toward games the user
      # already owns.
      def historical
        game_ids = RpgClubSteamAppGamedbMap
          .where(created_by: params[:user_id], status: "mapped")
          .distinct
          .pluck(:gamedb_game_id)

        render json: { data: game_ids }
      end
    end
  end
end
