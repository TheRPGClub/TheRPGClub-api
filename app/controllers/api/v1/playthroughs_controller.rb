# frozen_string_literal: true

module Api
  module V1
    # Playthroughs (spec api#457, ticket api#459; GLOSSARY.md "Playthrough"):
    # start one, set its total by hand, abandon it. A Game Completion closes it
    # (CompletionsController#create) and adding a game to Now Playing opens one
    # (NowPlayingController#create). Ungated.
    #
    # Writes are the member's own; a Superadmin (and the bot) may write for
    # anyone, as with Manual Playtime. Each answers with the game's Playtime
    # document (PlaytimeController#show), whose `playthrough` is the open one
    # and `playthroughs` the earlier ones.
    class PlaythroughsController < ApplicationController
      include PlaytimeDocument

      before_action :require_owner_or_superadmin!

      # POST /api/v1/users/:user_id/games/:game_id/playthroughs
      # Starts one, measured from the member's Playtime now. 409
      # `playthrough_open` when one is already open.
      def create
        user_id = RpgClubUser.find(params[:user_id]).user_id
        game_id = GamedbGame.find(params[:game_id]).game_id
        Playtime::Playthroughs.start!(user_id: user_id, game_id: game_id)
        render_playtime(user_id, game_id, status: :created)
      rescue Playtime::Playthroughs::AlreadyOpen => e
        render json: { error: "playthrough_open", message: e.message }, status: :conflict
      end

      # PATCH /api/v1/playthroughs/:id
      # Body: { "data": { "total_minutes": <n|null> } }
      # Sets its total by hand, replacing the measured time; null goes back to
      # the measured time. 409 `playthrough_closed` once it has ended.
      def update
        playthrough = UserGamePlaythrough.find(params[:id])
        total = request_data["total_minutes"]
        return refuse_total unless request_data.key?("total_minutes") &&
          (total.nil? || (total.is_a?(Integer) && total >= 0))

        Playtime::Playthroughs.set_total!(playthrough, total)
        render_playtime(playthrough.user_id, playthrough.gamedb_game_id)
      rescue Playtime::Playthroughs::Closed
        refuse_closed
      end

      # POST /api/v1/playthroughs/:id/abandon
      # Ends it as abandoned, keeping its time. 409 `playthrough_closed` once
      # it has ended.
      def abandon
        playthrough = UserGamePlaythrough.find(params[:id])
        Playtime::Playthroughs.abandon!(playthrough)
        render_playtime(playthrough.user_id, playthrough.gamedb_game_id)
      rescue Playtime::Playthroughs::Closed
        refuse_closed
      end

      private

      def refuse_total
        render json: { error: "invalid_total_minutes", message: "total_minutes must be a whole number of 0 or more, " \
                                                               "or null" }, status: :unprocessable_content
      end

      def refuse_closed
        render json: { error: "playthrough_closed", message: "this Playthrough has ended" }, status: :conflict
      end

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?

        UserGamePlaythrough.find_by(id: params[:id])&.user_id
      end
    end
  end
end
