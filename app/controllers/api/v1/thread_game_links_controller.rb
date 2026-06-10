# frozen_string_literal: true

module Api
  module V1
    # The thread ↔ game link table (#45), mirroring the bot's mergeThreadGameLink
    # / removeThreadGameLinks / deleteThreadGameLink. All actions are
    # service/admin-gated (the bot writes through the API). Every change
    # recomputes the thread's derived `gamedb_game_id` so it stays the MIN of the
    # remaining links (the bot's updateThreadsGameId), folded in here so the bot
    # doesn't need a separate call.
    class ThreadGameLinksController < ApplicationController
      before_action :require_admin_or_service!

      # POST /api/v1/threads/:id/links   { data: { gamedb_game_id: } }
      #
      # Idempotent merge: links the thread to the game, or returns the existing
      # link. `create_or_find_by!` is concurrency-safe (the composite PK absorbs
      # the race); the `belongs_to :game` validation rejects an unknown game with
      # 422. 201 when newly linked, 200 when it already was.
      def create
        thread = DiscordThread.find(params[:id])
        link = ThreadGameLink.create_or_find_by!(
          thread_id: thread.thread_id,
          gamedb_game_id: link_game_id
        )
        DiscordThread.recompute_primary_game!(thread.thread_id)

        render json: { data: ThreadGameLinkResource.new(link).serializable_hash },
          status: link.previously_new_record? ? :created : :ok
      end

      # DELETE /api/v1/threads/:id/links/:game_id
      #
      # Remove one game link from the thread (removeThreadGameLinks with a game).
      def destroy
        thread = DiscordThread.find(params[:id])
        count = ThreadGameLink
          .where(thread_id: thread.thread_id, gamedb_game_id: params[:game_id])
          .delete_all
        DiscordThread.recompute_primary_game!(thread.thread_id)
        render json: { deleted: true, count: count }
      end

      # DELETE /api/v1/threads/:id/links
      #
      # Remove every game link from the thread (deleteThreadGameLink).
      def destroy_all
        thread = DiscordThread.find(params[:id])
        count = ThreadGameLink.where(thread_id: thread.thread_id).delete_all
        DiscordThread.recompute_primary_game!(thread.thread_id)
        render json: { deleted: true, count: count }
      end

      private

      def link_game_id
        request_data.fetch("gamedb_game_id") { raise ActionController::ParameterMissing, "gamedb_game_id" }
      end
    end
  end
end
