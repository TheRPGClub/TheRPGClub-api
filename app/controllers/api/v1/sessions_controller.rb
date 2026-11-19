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

        access = pinned_access(user)
        render json: {
          principal: current_principal,
          membership: membership,
          features: access.session_features,
          **pinned_pages(user, access)
        }
      end

      private

      # The member's Pinned Pages (tickets api#418, api#419), so the sidebar
      # renders without another request: the visible list, whether they saved
      # their own (Settings offers a reset then), how many visible pins they
      # have room for, and the club's default and limit (the API owns both,
      # docs/adr/0012). None pinned for the service token.
      def pinned_pages(user, access)
        club = { pinned_pages_default: PinnedPages::DEFAULT, pinned_pages_limit: PinnedPages::LIMIT }
        unless current_principal.discord_user?
          return { pinned_pages: [], pinned_pages_customised: false, pinned_pages_room: PinnedPages::LIMIT, **club }
        end

        list = PinnedPages::List.new(current_principal.id.to_s, pinned_viewer(access), user)
        { pinned_pages: list.visible, pinned_pages_customised: list.customised?, pinned_pages_room: list.room, **club }
      end
    end
  end
end
