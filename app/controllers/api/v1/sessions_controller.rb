# frozen_string_literal: true

module Api
  module V1
    class SessionsController < ApplicationController
      def show
        user = RpgClubUser.find_by(user_id: current_principal.discord_id) if current_principal.discord_user?
        membership = user&.membership
        if membership
          membership = membership.merge(
            dev: current_principal.dev?,
            longstanding: current_principal.longstanding?
          )
        end

        render json: {
          principal: current_principal,
          membership: membership
        }
      end
    end
  end
end
