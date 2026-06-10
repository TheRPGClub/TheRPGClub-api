# frozen_string_literal: true

module Api
  module V1
    # Per-user activity icons the bot captured from Discord rich presence (bot
    # parity, #46). Read-only: the bot's presence loop owns every write.
    class UserActivityIconsController < ApplicationController
      # GET /api/v1/users/:user_id/activity_icons
      def index
        scope = RpgClubUserActivityIcon.where(user_id: params[:user_id])
        render_collection(scope, resource: UserActivityIconResource,
          default_order: { last_seen_at: :desc, id: :desc })
      end
    end
  end
end
