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

      # GET /api/v1/users/avatar_history_counts
      #
      # Aggregate avatar-change count per active, non-bot member, backing the
      # bot's avatar-history leaderboard (`getAllMembersAvatarHistoryCounts`,
      # #145). Mirrors that SQL exactly: an inner join to the history log (so
      # only members with at least one logged change appear), active members
      # only (`server_left_at IS NULL`), bots excluded, ordered by display name
      # (`global_name`, then `username`, then `user_id`). A grouped aggregate, so
      # the count is computed explicitly and handed to pagy — its grouped-count
      # path would otherwise return a per-group hash. A `user_id` tiebreaker
      # keeps pagination stable when two members share a display name.
      def counts
        base = RpgClubUser.where(server_left_at: nil, is_bot: false).joins(:avatar_history)

        count = base.distinct.count(:user_id)
        ranked = base
          .group("rpg_club_users.user_id", "rpg_club_users.username", "rpg_club_users.global_name")
          .select(
            "rpg_club_users.user_id AS user_id",
            "rpg_club_users.username AS username",
            "rpg_club_users.global_name AS global_name",
            "COUNT(rpg_club_user_avatar_history.event_id) AS avatar_change_count"
          )
          .order(Arel.sql(
            "COALESCE(rpg_club_users.global_name, rpg_club_users.username, rpg_club_users.user_id) ASC, " \
            "rpg_club_users.user_id ASC"
          ))

        pagy, records = pagy(ranked, count: count, **pagy_options)
        render json: {
          data: AvatarHistoryCountResource.new(records).serializable_hash,
          meta: pagy_meta(pagy)
        }
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
