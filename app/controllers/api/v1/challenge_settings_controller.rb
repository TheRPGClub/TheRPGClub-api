# frozen_string_literal: true

module Api
  module V1
    # The member's Challenge settings (spec #376, ticket #379): so far their
    # Challenge DM opt-out, `dms`, stored as `rpg_club_users.challenge_dms`
    # next to their other notification preference. The lifecycle job sends
    # Challenge reminder DMs (`challenge_dm`) only while it is on, which it is
    # until the member turns it off.
    #
    # The member's own: they, or the bot acting for them, read and change it.
    # PATCH creates the member's record when the API has none yet, like the
    # other member settings.
    class ChallengeSettingsController < ApplicationController
      feature :challenges

      before_action :require_owner!

      BOOLEANS = [ true, false, "true", "false" ].freeze

      # GET /api/v1/users/:user_id/challenge_settings
      def show
        dms = RpgClubUser.where(user_id: params[:user_id]).pick(:challenge_dms)
        render json: { data: settings(params[:user_id], dms.nil? || dms) }
      end

      # PATCH /api/v1/users/:user_id/challenge_settings
      # Body: { "data": { "dms": true|false } }
      def update
        dms = request_data["dms"]
        unless BOOLEANS.include?(dms)
          return render json: { error: "invalid_settings", message: "dms must be true or false" },
            status: :unprocessable_content
        end

        user = RpgClubUser.find_or_initialize_by(user_id: params[:user_id])
        user.update!(challenge_dms: ActiveModel::Type::Boolean.new.cast(dms))
        render json: { data: settings(user.user_id, user.challenge_dms) }
      end

      private

      def settings(user_id, dms) = { user_id: user_id, dms: dms }
    end
  end
end
