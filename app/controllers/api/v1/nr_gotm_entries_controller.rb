# frozen_string_literal: true

module Api
  module V1
    class NrGotmEntriesController < ApplicationController
      def index
        scope = NrGotmEntry.all
        scope = scope.where(round_number: params[:round_number]) if params[:round_number].present?
        scope = scope.preload(game: :images) if include_game?
        render_collection(
          scope,
          resource: NrGotmEntryResource,
          default_order: { round_number: :desc, game_index: :asc },
          params: { include_game: include_game? }
        )
      end

      def show
        scope = include_game? ? NrGotmEntry.preload(game: :images) : NrGotmEntry
        entry = scope.find(params[:id])
        render json: { data: NrGotmEntryResource.new(entry, params: { include_game: include_game? }).serializable_hash }
      end

      private

      def include_game?
        params[:include].to_s.split(",").map(&:strip).include?("game")
      end
    end
  end
end
