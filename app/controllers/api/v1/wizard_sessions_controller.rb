# frozen_string_literal: true

module Api
  module V1
    # Admin wizard session persistence (#162). Backs the Discord bot's
    # `/admin nextround-setup` wizard as it migrates off direct SQL
    # (`rpg_club_admin_wizard_sessions`, adminWizardSession.sql.ts) onto the API.
    #
    # A session is keyed by (command_key, owner_user_id, channel_id); at most one
    # active session may exist per key, enforced by the partial unique index
    # added in #160 (`ux_rpg_club_admin_wiz_one_active`). Reads/writes are
    # owner-only (the bot's service token counts as the owner, per
    # `require_owner!`).
    class WizardSessionsController < ApplicationController
      before_action :require_owner!, only: %i[user_index upsert update destroy destroy_historical]

      # GET /api/v1/users/:user_id/wizard_sessions?command_key=...&channel_id=...
      #
      # The single active session for this (command_key, owner, channel), or 404.
      def user_index
        record = RpgClubAdminWizardSession.find_by!(
          owner_user_id: params[:user_id],
          command_key: params.require(:command_key),
          channel_id: params.require(:channel_id),
          status: "active"
        )
        render json: { data: WizardSessionResource.new(record).serializable_hash }
      end

      # POST /api/v1/users/:user_id/wizard_sessions
      # Body: { "data": { "command_key", "channel_id", "guild_id", "state_json" } }
      #
      # Upserts the active session for this (command_key, owner, channel) — the
      # bot's resumable-wizard save, called after every step.
      def upsert
        data = request_data
        %w[command_key channel_id state_json].each do |key|
          next if data[key].present?

          return render json: { error: "#{key} is required" }, status: :bad_request
        end

        record = RpgClubAdminWizardSession.find_or_initialize_by(
          owner_user_id: params[:user_id],
          command_key: data["command_key"],
          channel_id: data["channel_id"],
          status: "active"
        )
        record.guild_id = data["guild_id"]
        record.state_json = data["state_json"]
        record.last_updated_at = Time.current
        record.save!

        render json: { data: WizardSessionResource.new(record).serializable_hash }
      end

      # PATCH /api/v1/wizard_sessions/:id
      # Body: { "data": { "status" } }
      def update
        status = request_data["status"]
        return render json: { error: "status is required" }, status: :bad_request if status.blank?

        record = RpgClubAdminWizardSession.find(params[:id])
        record.update!(status: status)
        render json: { data: WizardSessionResource.new(record).serializable_hash }
      end

      # DELETE /api/v1/wizard_sessions/:id
      def destroy
        RpgClubAdminWizardSession.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      # DELETE /api/v1/users/:user_id/wizard_sessions?command_key=...&channel_id=...
      #
      # Bulk-deletes every non-active (historical) session for this key — the
      # bot's deleteHistorical, run before promoting a session to
      # completed/cancelled. `command_key`/`channel_id` are required so this can
      # never wipe more than one wizard's history in one call.
      def destroy_historical
        count = RpgClubAdminWizardSession.where(
          owner_user_id: params[:user_id],
          command_key: params.require(:command_key),
          channel_id: params.require(:channel_id)
        ).where.not(status: "active").delete_all

        render json: { deleted: true, count: count }
      end

      private

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        RpgClubAdminWizardSession.find_by(session_id: params[:id])&.owner_user_id
      end
    end
  end
end
