# frozen_string_literal: true

module Api
  module V1
    # GET /api/v1/users/:user_id/feature_access
    #
    # Service-only Feature access lookup for the bot's feature gate (spec #347,
    # docs/adr/0005): every Feature's state and whether this Discord user can
    # use it. Staff (Admin or Superadmin) is read from the member's stored
    # roles, which the bot keeps current with its role reports, so the bot never
    # decides who is staff. A Discord user with no member record is not staff.
    class FeatureAccessController < ApplicationController
      before_action :require_service!

      def show
        user = RpgClubUser.without_images.find_by(user_id: params[:user_id])
        access = Features::Access.for_member(user)

        render json: {
          data: { user_id: params[:user_id], staff: access.staff?, features: access.lookup_features }
        }
      end
    end
  end
end
