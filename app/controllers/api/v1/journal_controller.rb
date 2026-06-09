# frozen_string_literal: true

module Api
  module V1
    # Per-game journal feature (bot parity, #39). Entries belong to a
    # (user, game) pair and are all public — there is no visibility concept.
    class JournalController < ApplicationController
      before_action :require_owner!, only: %i[create update destroy]

      # GET /api/v1/users/:user_id/journal
      #
      # The games a user has journaled, with per-game entry counts and the
      # last-entry timestamp. Bounded per user (you journal tens of games, not
      # thousands), so it returns the whole list ordered by title rather than
      # paginating.
      def index
        aggregates = UserGameJournalEntry
          .where(user_id: params[:user_id])
          .group(:gamedb_game_id)
          .pluck(:gamedb_game_id, Arel.sql("COUNT(*)"), Arel.sql("MAX(created_at)"))

        games = GamedbGame.without_images.where(game_id: aggregates.map(&:first)).preload(:images).index_by(&:game_id)

        data = aggregates.filter_map do |game_id, entry_count, last_entry_at|
          game = games[game_id]
          next unless game

          {
            "game" => GameSummaryResource.new(game).serializable_hash,
            "entry_count" => entry_count,
            "last_entry_at" => last_entry_at
          }
        end.sort_by { |row| row["game"]["title"].to_s.downcase }

        render json: { data: data }
      end

      # GET /api/v1/games/:id/journal
      #
      # Journal entries for a game across users. An optional `user_id` query
      # param narrows to a single author.
      def game_index
        scope = UserGameJournalEntry.where(gamedb_game_id: params[:id]).includes(:user)
        scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?

        render_collection(scope, resource: JournalEntryUserResource,
          default_order: { created_at: :desc, entry_id: :desc })
      end

      # GET /api/v1/journal_entries/:id
      def show
        record = UserGameJournalEntry.includes(:game).find(params[:id])
        render json: { data: JournalEntryGameResource.new(record).serializable_hash }
      end

      # POST /api/v1/users/:user_id/journal
      def create
        record = UserGameJournalEntry.create!(request_data.merge("user_id" => params[:user_id]))
        record.reload
        render json: { data: JournalEntryGameResource.new(record).serializable_hash }, status: :created
      end

      # PATCH/PUT /api/v1/journal_entries/:id
      def update
        record = UserGameJournalEntry.find(params[:id])
        record.update!(request_data)
        record.reload
        render json: { data: JournalEntryGameResource.new(record).serializable_hash }
      end

      # DELETE /api/v1/journal_entries/:id
      def destroy
        UserGameJournalEntry.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        UserGameJournalEntry.find_by(entry_id: params[:id])&.user_id
      end
    end
  end
end
