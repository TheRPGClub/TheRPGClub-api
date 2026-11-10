# frozen_string_literal: true

module Api
  module V1
    # PUT /api/v1/users/:user_id/roles
    #
    # Service-only role report. The bot sends a member's current Discord role
    # IDs when Discord reports a guild member update; the Superadmin (dev),
    # Admin, Moderator, Regulars and Members flags are replaced with the ones
    # those roles grant (DiscordRoles::USER_FLAG_ROLES), the same derivation
    # sign-in uses.
    class UserRolesController < ApplicationController
      before_action :require_service!

      def update
        role_ids = request_data["role_ids"]
        unless role_ids.is_a?(Array)
          return render(json: { error: "role_ids must be an array" }, status: :unprocessable_entity)
        end

        user = RpgClubUser.without_images.find(params[:user_id])
        user.apply_discord_roles!(role_ids)

        render json: { data: { user_id: user.user_id, membership: user.membership } }
      end
    end
  end
end
