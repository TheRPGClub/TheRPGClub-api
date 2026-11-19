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

        pins = pinned_list(user)
        render json: {
          principal: current_principal,
          membership: membership,
          features: Features::Access.for_viewer(user, staff: admin_or_above?).session_features,
          pinned_pages: pins ? pins.visible : [],
          pinned_pages_customised: pins ? pins.customised? : false
        }
      end

      private

      # The member's Pinned Pages (tickets api#418, api#419): the visible list,
      # so the sidebar renders without another request, and whether they
      # saved their own (Settings offers a reset then). None for the service
      # token.
      def pinned_list(user)
        return unless current_principal.discord_user?

        PinnedPages::List.new(current_principal.id.to_s, pinned_viewer(user))
      end
    end
  end
end
