# frozen_string_literal: true

module Api
  module V1
    class SessionsController < ApplicationController
      include PinnedPagesViewer

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
          membership: membership,
          features: Features::Access.for_viewer(user, staff: admin_or_above?).session_features,
          pinned_pages: pinned_pages(user)
        }
      end

      private

      # The member's visible Pinned Pages (ticket api#418), so the sidebar
      # renders without another request. Empty for the service token.
      def pinned_pages(user)
        return [] unless current_principal.discord_user?

        PinnedPages::List.new(current_principal.id.to_s, pinned_viewer(user)).visible
      end
    end
  end
end
