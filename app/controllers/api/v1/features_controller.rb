# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/features and PATCH /api/v1/features/:key
    #
    # Staff flag control (spec #347): Admins and Superadmins see every Feature
    # with its Feature Flag state, Core/hideable, coverage and last change, and
    # set a Feature Off, Preview or Live with an optional reason.
    #
    # A member signs in with their session and is staff by the existing staff
    # gates. The bot calls with the service token and names the acting Discord
    # user (`acting_user_id`); the same Admin/Superadmin rule then applies to
    # that member's stored roles, never to the token (docs/adr/0005).
    #
    # Not behind the feature gate: the staff desk is not part of any Feature.
    class FeaturesController < ApplicationController
      before_action :require_flag_staff!

      # GET /api/v1/features[?acting_user_id=]
      def index
        render json: { data: Features::StaffList.new.entries }
      end

      # PATCH /api/v1/features/:key
      # Body: { "data": { "state": "off|preview|live", "reason": "...", "acting_user_id": "..." (bot only) } }
      # 404 for a key that is not a Feature, 422 for an invalid state or reason.
      def update
        data = request_data
        unless Features.known?(params[:key])
          return render json: { error: "not_found" }, status: :not_found
        end

        change = Features::ChangeFlag.call(params[:key], data["state"], by: acting_user_id, reason: data["reason"])
        render json: { data: Features::StaffList.new.entry_for(params[:key]), meta: { changed: change.present? } }
      rescue Features::ChangeFlag::Invalid => error
        render json: { error: error.message }, status: :unprocessable_content
      end

      private

      # The member the request acts for, by Discord user id: the session's
      # member, or the bot's named acting user.
      def acting_user_id
        @acting_user_id ||=
          if current_principal.service?
            (action_name == "update" ? params.dig(:data, :acting_user_id) : params[:acting_user_id]).presence&.to_s
          else
            current_principal.id.to_s
          end
      end

      def require_flag_staff!
        if current_principal.service?
          if acting_user_id.blank?
            return render json: { error: "acting_user_id required" }, status: :bad_request
          end

          gate_or_forbid(Features::Access.staff_member?(RpgClubUser.without_images.find_by(user_id: acting_user_id)))
        else
          require_admin_or_above!
        end
      end
    end
  end
end
