# frozen_string_literal: true

module Api
  module V1
    # Discord threads the bot maps to games (#45). The bot writes these tables
    # (upsertThread / setSkipLinking / link merge+remove) — this controller lets
    # it do so through the API as the service principal instead of via direct
    # SQL. Writes are service/admin-gated; reads are open to any authenticated
    # caller, matching the rest of the bot-managed read endpoints. The link
    # writes live in ThreadGameLinksController.
    class ThreadsController < ApplicationController
      before_action :require_admin_or_service!, only: %i[create update]

      # GET /api/v1/games/:id/threads
      #
      # The threads linked to the game through `thread_game_links` (a thread can
      # be linked to several games), newest thread first.
      def game_index
        scope = DiscordThread
          .joins(:thread_game_links)
          .where(thread_game_links: { gamedb_game_id: params[:id] })
        render_collection(scope, resource: ThreadResource, default_order: { created_at: :desc })
      end

      # GET /api/v1/threads/:id
      #
      # A single thread plus its full game-link list under `links` (the bot's
      # getThreadGameLinks — a thread can map to several games, beyond the
      # derived `gamedb_game_id` primary).
      def show
        thread = DiscordThread.includes(:thread_game_links).find(params[:id])
        data = ThreadResource.new(thread).serializable_hash
        data["links"] = ThreadGameLinkResource.new(thread.thread_game_links).serializable_hash
        render json: { data: data }
      end

      # POST /api/v1/threads
      #
      # Upsert a thread by `thread_id` (a client-supplied Discord snowflake),
      # mirroring the bot's upsertThread: inserts a new row, or on an existing
      # one refreshes only SYNC_COLUMNS so a sync sweep can't reset the admin's
      # `skip_linking` or the original `created_at`. The derived `gamedb_game_id`
      # is never written here (see #writable_data). Returns 201 on insert, 200 on
      # update.
      def create
        data = writable_data
        thread_id = data["thread_id"].presence
        raise ActionController::ParameterMissing, "thread_id" if thread_id.nil?

        thread = DiscordThread.find_or_initialize_by(thread_id: thread_id)
        created = thread.new_record?
        thread.assign_attributes(created ? data : data.slice(*DiscordThread::SYNC_COLUMNS))
        thread.save!

        render json: { data: ThreadResource.new(thread).serializable_hash },
          status: created ? :created : :ok
      end

      # PATCH/PUT /api/v1/threads/:id
      #
      # Partial update of any mutable thread column — including `skip_linking`
      # (the bot's setSkipLinking), `is_archived`, `thread_name`, `last_seen_at`.
      # The PK and the derived `gamedb_game_id` can't be changed here.
      def update
        thread = DiscordThread.find(params[:id])
        thread.update!(writable_data.except("thread_id"))
        thread.reload
        render json: { data: ThreadResource.new(thread).serializable_hash }
      end

      private

      # `gamedb_game_id` is server-derived (MIN of the thread's links, kept
      # current by ThreadGameLink changes via DiscordThread.recompute_primary_game!),
      # so it's stripped from every write.
      def writable_data
        request_data.except("gamedb_game_id")
      end
    end
  end
end
