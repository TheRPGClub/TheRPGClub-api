# frozen_string_literal: true

module Api
  module V1
    # A member's Playtime for one game (spec api#457, ticket api#458; ADR
    # 0015): the total, the breakdown per Provider set and Manual entry, and
    # the mismatches, as Playtime::Ledger works them out. Ungated.
    #
    # Any signed-in caller reads it, as with Completions. Settling a mismatch
    # is the member's own, or a Superadmin's (and the bot's) for anyone.
    class PlaytimeController < ApplicationController
      include PlaytimeDocument

      KEEPS = %w[manual provider both].freeze

      before_action :require_owner_or_superadmin!, only: :settle_mismatch

      # GET /api/v1/users/:user_id/games/:game_id/playtime
      def show
        user = RpgClubUser.find(params[:user_id])
        game = GamedbGame.find(params[:game_id])
        render_playtime(user.user_id, game.game_id)
      end

      # POST /api/v1/users/:user_id/games/:game_id/playtime/mismatches
      # Body: { "data": { "platform_id": <id>, "keep": "manual" | "provider" | "both" } }
      # Keep mine sets the Manual entry's `keeps_over_provider` to the Provider
      # reporting that platform, so its figure stops counting there; keep the
      # Provider's deletes the Manual entry; keep both sets the entry's
      # `mismatch_acknowledged_provider`, so both figures count and the pair
      # is no longer a mismatch (ADR 0015). 422 `no_mismatch` when the
      # platform has none.
      def settle_mismatch
        keep = request_data["keep"]
        unless KEEPS.include?(keep)
          return render(json: { error: "invalid_keep", message: "keep must be manual, provider or both" },
            status: :unprocessable_content)
        end

        user_id = RpgClubUser.find(params[:user_id]).user_id
        game_id = GamedbGame.find(params[:game_id]).game_id
        mismatch = Playtime::Ledger.for_game(user_id: user_id, game_id: game_id).mismatches
          .find { |candidate| candidate.platform_id.to_s == request_data["platform_id"].to_s }
        unless mismatch
          return render(json: { error: "no_mismatch", message: "there is no mismatch on that platform" },
            status: :unprocessable_content)
        end

        entry = UserGameManualPlaytime.find(mismatch.manual_playtime_id)
        case keep
        when "manual" then entry.update!(keeps_over_provider: mismatch.provider)
        when "both" then entry.update!(mismatch_acknowledged_provider: mismatch.provider)
        else entry.destroy!
        end
        render_playtime(user_id, game_id)
      end
    end
  end
end
