# frozen_string_literal: true

module Api
  module V1
    # Bot presence history (#94). Backs the Discord bot's `/setpresence` flow
    # as it migrates `BotPresenceHistory` off direct SQL (RPGClub_GameDB#795):
    # the bot records each presence change and reads back the latest (to
    # restore presence on boot) or the recent history.
    #
    # Every action is open to Moderator and up (the bot's `/mod presence`) and
    # the service (#335). A staff create is the site setting the presence: the
    # setter comes from the session and a `presence_set` job makes the bot
    # apply it at once instead of at its hourly re-assert.
    class BotPresenceController < ApplicationController
      before_action :require_moderator_or_above!

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
      # we reload to return the stamped value. The bot has already applied its
      # own writes; a staff write queues `presence_set` in the same transaction,
      # returned as `meta.presence_job_id` (null when none was queued).
      def create
        record, presence_job = BotPresenceHistory.transaction do
          next [ BotPresenceHistory.create!(writable_data), nil ] if current_principal.service?

          entry = BotPresenceHistory.new(staff_data)
          entry.save!(context: :staff)
          [ entry, enqueue_presence_set(entry) ]
        end
        record.reload
        render json: { data: BotPresenceResource.new(record).serializable_hash,
                       meta: { presence_job_id: presence_job&.id } }, status: :created
      end

      private

      # `id` is the auto-generated PK and `set_at` is DB-stamped, so both are
      # server-managed and stripped from any write.
      def writable_data
        request_data.except("id", "set_at")
      end

      # A staff setter is the session member, never what the body claims.
      def staff_data
        writable_data.merge(
          "set_by_user_id" => current_principal.id,
          "set_by_username" => current_principal.username.presence ||
            RpgClubUser.where(user_id: current_principal.id).pick(:username)
        )
      end

      def enqueue_presence_set(entry)
        BotJob.enqueue!(
          kind: "presence_set",
          summary: %(Set the bot's presence to "#{entry.activity_name}"),
          payload: { activity_name: entry.activity_name },
          requested_by: current_principal.id
        )
      end
    end
  end
end
