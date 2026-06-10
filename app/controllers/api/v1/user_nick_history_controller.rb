# frozen_string_literal: true

module Api
  module V1
    # Per-user nickname change history (bot parity, #49). Read-only: the bot's
    # member domain owns every write.
    class UserNickHistoryController < ApplicationController
      # GET /api/v1/users/:user_id/nick_history
      def index
        scope = RpgClubUserNickHistory.where(user_id: params[:user_id])
        render_collection(scope, resource: UserNickHistoryResource,
          default_order: { changed_at: :desc, event_id: :desc })
      end
    end
  end
end
