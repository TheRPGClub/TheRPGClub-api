# frozen_string_literal: true

module Api
  module V1
    # Franchise suggestions for a game (spec api#487, ticket api#489): up to
    # three Franchises it probably belongs to, each with a reason and a
    # likely role (Gamedb::FranchiseSuggestions). Read by those who may
    # change Franchises (FranchiseRights: Regulars and above; the bot names
    # its member in `acting_user_id`).
    class FranchiseSuggestionsController < ApplicationController
      include FranchiseRights

      # GET /api/v1/games/:id/franchise_suggestions
      def index
        return unless require_editor!

        game = GamedbGame.select(:game_id, :title, :collection_id, :parent_igdb_id).find(params[:id])
        render json: { data: Gamedb::FranchiseSuggestions.for(game) }
      end
    end
  end
end
