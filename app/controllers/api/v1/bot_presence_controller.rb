# frozen_string_literal: true

module Api
  module V1
    # Bot presence history (service-only, #94). Backs the Discord bot's
    # `/setpresence` flow as it migrates `BotPresenceHistory` off direct SQL
    # (RPGClub_GameDB#795): the bot records each presence change and reads back
    # the latest (to restore presence on boot) or the recent history.
    #
    # Every action is service-only — only the bot's bearer token may touch this.
    class BotPresenceController < ApplicationController
      before_action :require_service!

      # The bot caps its history reads at 50 rows (getPresenceHistory), so the
      # list never serves more than 50 per page.
      MAX_LIMIT = 50

      # GET /api/v1/bot_presence
      #
      # Lists presence history, newest first. The `limit` param (capped at 50)
      # sizes the page; `id` is the tiebreaker for rows sharing a `set_at`.
      def index
        render_collection(
          BotPresenceHistory.all,
          resource: BotPresenceResource,
          default_order: { set_at: :desc, id: :desc },
          default_per: MAX_LIMIT,
          max_per: MAX_LIMIT
        )
      end

      # GET /api/v1/bot_presence/latest
      #
      # Returns the most recent entry, or `{ data: null }` when none exist (the
      # bot treats null as "no presence to restore").
      def latest
        record = BotPresenceHistory.order(set_at: :desc, id: :desc).first
        data = record ? BotPresenceResource.new(record).serializable_hash : nil
        render json: { data: data }
      end

      # POST /api/v1/bot_presence
      #
      # Records a new presence entry. `set_at` defaults to now() in the DB, so
      # we reload to return the stamped value.
      def create
        record = BotPresenceHistory.create!(writable_data)
        record.reload
        render json: { data: BotPresenceResource.new(record).serializable_hash }, status: :created
      end

      private

      # `id` is the auto-generated PK and `set_at` is DB-stamped, so both are
      # server-managed and stripped from any write.
      def writable_data
        request_data.except("id", "set_at")
      end
    end
  end
end
