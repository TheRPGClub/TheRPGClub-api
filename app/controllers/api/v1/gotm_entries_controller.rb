# frozen_string_literal: true

module Api
  module V1
    # Game of the Month entries. Reads are open to any authenticated caller; the
    # write actions (POST/PATCH/DELETE) are admin/service-gated and let the bot
    # manage rounds via the API instead of direct SQL (#98). Each row is one game
    # slot in a round — the bot POSTs once per game for multi-game months.
    class GotmEntriesController < ApplicationController
      before_action :require_admin_or_service!, only: %i[create update destroy]

      # Settable on create: the round identity plus the game. `month_year`,
      # `game_index` and `gamedb_game_id` are required; `reddit_url` is optional.
      # `voting_results_message_id` is bot-managed delivery state set later via
      # PATCH, so it starts NULL and is not accepted here.
      CREATE_ATTRS = %w[round_number month_year game_index gamedb_game_id reddit_url].freeze
      # Settable on update: the mutable fields only. The round identity
      # (`round_number`, `month_year`, `game_index`) is fixed once created.
      UPDATE_ATTRS = %w[reddit_url gamedb_game_id voting_results_message_id].freeze

      def index
        scope = GotmEntry.all
        scope = scope.where(round_number: params[:round_number]) if params[:round_number].present?
        scope = scope.preload(game: :images) if include_game?
        render_collection(
          scope,
          resource: GotmEntryResource,
          default_order: { round_number: :desc, game_index: :asc },
          params: { include_game: include_game? }
        )
      end

      def show
        scope = include_game? ? GotmEntry.preload(game: :images) : GotmEntry
        entry = scope.find(params[:id])
        render json: { data: GotmEntryResource.new(entry, params: { include_game: include_game? }).serializable_hash }
      end

      def create
        entry = GotmEntry.create!(request_data.slice(*CREATE_ATTRS))
        entry.reload
        render json: { data: GotmEntryResource.new(entry).serializable_hash }, status: :created
      end

      def update
        entry = GotmEntry.find(params[:id])
        entry.update!(request_data.slice(*UPDATE_ATTRS))
        entry.reload
        render json: { data: GotmEntryResource.new(entry).serializable_hash }
      end

      def destroy
        GotmEntry.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      def include_game?
        params[:include].to_s.split(",").map(&:strip).include?("game")
      end
    end
  end
end
