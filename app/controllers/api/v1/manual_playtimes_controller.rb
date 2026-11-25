# frozen_string_literal: true

module Api
  module V1
    # Manual Playtime (spec api#457, ticket api#458; GLOSSARY.md "Manual
    # Playtime"): time a member records for a game on one platform (null is
    # "Other"), one entry per platform. Ungated.
    #
    # Writes are the member's own; a Superadmin (and the bot, acting for the
    # member who ran `/playtime add`) may write for anyone, as with
    # Completions. Every write answers with the game's Playtime for that member
    # (the PlaytimeController#show document), so a client can show the new
    # total and breakdown at once.
    class ManualPlaytimesController < ApplicationController
      include PlaytimeDocument

      MODES = %w[add set].freeze

      before_action :require_owner_or_superadmin!

      # POST /api/v1/users/:user_id/games/:game_id/manual_playtimes
      # Body: { "data": { "platform_id": <id|null>, "minutes": <n>, "mode": "add" | "set", "note": <text> } }
      # Creates the entry for that platform or changes it: `add` (the default)
      # raises its minutes, `set` replaces them. A `note` replaces the note;
      # leaving it out keeps it.
      def create
        mode = request_data.fetch("mode", "add")
        return refuse("invalid_mode", "mode must be add or set") unless MODES.include?(mode)
        return refuse("invalid_minutes", "minutes must be a whole number of 0 or more") unless minutes_valid?
        return if platform_unknown?

        user_id = RpgClubUser.find(params[:user_id]).user_id
        game_id = GamedbGame.find(params[:game_id]).game_id
        write_entry(user_id, game_id, mode)
        render_playtime(user_id, game_id)
      end

      # PATCH /api/v1/manual_playtimes/:id
      # Body: { "data": { "minutes": <n>, "note": <text>, "platform_id": <id|null> } }, each optional.
      # `minutes` sets the total. Moving the entry to another platform clears
      # its "keep mine" choice, which was about the old platform.
      def update
        entry = UserGameManualPlaytime.find(params[:id])
        return refuse("invalid_minutes", "minutes must be a whole number of 0 or more") if
          request_data.key?("minutes") && !minutes_valid?
        return if request_data.key?("platform_id") && platform_unknown?

        entry.assign_attributes(request_data.slice("minutes", "note", "platform_id"))
        entry.keeps_over_provider = nil if entry.platform_id_changed?
        entry.save!
        render_playtime(entry.user_id, entry.gamedb_game_id)
      end

      # DELETE /api/v1/manual_playtimes/:id
      def destroy
        entry = UserGameManualPlaytime.find(params[:id])
        entry.destroy!
        render_playtime(entry.user_id, entry.gamedb_game_id)
      end

      private

      # Two first adds at once race to create the entry; the loser retries
      # once and then finds it, locked.
      def write_entry(user_id, game_id, mode, retried: false)
        UserGameManualPlaytime.transaction(requires_new: true) do
          entry = UserGameManualPlaytime.lock
            .find_or_initialize_by(user_id: user_id, gamedb_game_id: game_id, platform_id: request_data["platform_id"])
          minutes = request_data["minutes"]
          entry.minutes = mode == "add" ? entry.minutes + minutes : minutes
          entry.note = request_data["note"] if request_data.key?("note")
          entry.save!
        end
      rescue ActiveRecord::RecordNotUnique
        raise if retried

        write_entry(user_id, game_id, mode, retried: true)
      end

      def minutes_valid?
        minutes = request_data["minutes"]
        minutes.is_a?(Integer) && minutes >= 0
      end

      # Renders 422 for a platform id that isn't in GameDB; null is "Other".
      def platform_unknown?
        platform_id = request_data["platform_id"]
        return false if platform_id.nil? || GamedbPlatform.exists?(platform_id: platform_id)

        refuse("unknown_platform", "unknown platform: #{platform_id}")
        true
      end

      def refuse(error, message)
        render json: { error: error, message: message }, status: :unprocessable_content
      end

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?

        UserGameManualPlaytime.find_by(id: params[:id])&.user_id
      end
    end
  end
end
