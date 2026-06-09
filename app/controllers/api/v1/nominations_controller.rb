# frozen_string_literal: true

module Api
  module V1
    # GOTM / Non-RPG GOTM nominations for a voting round (bot parity, #40).
    # The winners are served by gotm_entries / nr_gotm_entries; these list the
    # field of candidates behind a round, each with its nominator and game.
    class NominationsController < ApplicationController
      # GET /api/v1/gotm_entries/:round/nominations
      def gotm
        render_nominations(GotmNomination)
      end

      # GET /api/v1/nr_gotm_entries/:round/nominations
      def nr_gotm
        render_nominations(NrGotmNomination)
      end

      private

      # Nominations for the round in the path, oldest first, each carrying its
      # embedded nominator and game (with images, so the game summary's cover /
      # art / logo URLs resolve without an N+1).
      def render_nominations(model)
        scope = model.where(round_number: params[:round]).preload(:user, game: :images)

        render_collection(scope, resource: NominationResource,
          default_order: { nominated_at: :asc, nomination_id: :asc })
      end
    end
  end
end
