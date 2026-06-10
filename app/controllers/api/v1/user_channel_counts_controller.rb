# frozen_string_literal: true

module Api
  module V1
    # Per-user, per-channel message counts the bot maintains by scanning
    # channel history (bot parity, #47). Read-only: the bot owns every write.
    class UserChannelCountsController < ApplicationController
      # GET /api/v1/users/:user_id/channel_counts
      def index
        scope = RpgClubUserChannelCount.where(user_id: params[:user_id])
        render_collection(scope, resource: UserChannelCountResource,
          default_order: { message_count: :desc, channel_id: :asc })
      end
    end
  end
end
