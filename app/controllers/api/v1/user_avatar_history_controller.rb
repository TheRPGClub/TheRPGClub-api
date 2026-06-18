# frozen_string_literal: true

module Api
  module V1
    # Per-user avatar change history (#105). The bot logs a row each time a
    # member's Discord avatar changes; clients (and the bot itself) read the
    # paginated history back.
    #
    # Reads are open to any authenticated caller; the write is service-only —
    # only the bot's bearer token records new avatar events.
    class UserAvatarHistoryController < ApplicationController
      before_action :require_service!, only: %i[create]

      # GET /api/v1/users/:user_id/avatar_history
      def index
        scope = RpgClubUserAvatarHistory.where(user_id: params[:user_id])
        render_collection(scope, resource: UserAvatarHistoryResource,
          default_order: { changed_at: :desc, event_id: :desc })
      end

      # POST /api/v1/users/:user_id/avatar_history
      #
      # Records a new avatar event. `event_id` is an identity column and
      # `changed_at` is DB-stamped, so both are server-managed; we reload to
      # return the stamped values.
      def create
        record = RpgClubUserAvatarHistory.create!(writable_data.merge(user_id: params[:user_id]))
        record.reload
        render json: { data: UserAvatarHistoryResource.new(record).serializable_hash }, status: :created
      end

      private

      # The bot supplies only the Discord avatar hash and its URL; `event_id`,
      # `user_id` (path), `changed_at` (DB default) and the binary `avatar_blob`
      # are never client-set here.
      def writable_data
        request_data.slice("avatar_hash", "avatar_url")
      end
    end
  end
end
