# frozen_string_literal: true

module Api
  module V1
    class GamesController < ApplicationController
      def index
        scope = params[:q].present? ? GamedbGame.search(params[:q]) : GamedbGame.without_images.order(:title)
        scope = apply_winner_filter(scope)
        records = scope.preload(:images).limit(limit).offset(offset)

        render json: {
          data: records.as_json,
          meta: {
            resource: "gamedb_games",
            limit: limit,
            offset: offset,
            total: scope.except(:select, :order).count(:all)
          }
        }
      end

      def show
        game = GamedbGame.without_images.find(params[:id])
        now_playing = UserNowPlaying
          .where(gamedb_game_id: game.game_id)
          .includes(:user)
          .order(added_at: :desc)
        completions = UserGameCompletion
          .where(gamedb_game_id: game.game_id)
          .includes(:user)
          .order(completed_at: :desc)

        render json: {
          data: game.as_json.merge(
            "gotm_month_year" => game.gotm_won ? game.gotm_entries.order(round_number: :desc).pick(:month_year) : nil,
            "nr_gotm_month_year" => game.nr_gotm_won ? game.nr_gotm_entries.order(round_number: :desc).pick(:month_year) : nil,
            "now_playing" => NowPlayingUserEntryResource.new(now_playing).serializable_hash,
            "completions" => CompletionUserEntryResource.new(completions).serializable_hash
          )
        }
      end

      def refresh_images
        return unless require_admin_or_service!

        result = Gamedb::IgdbImageImporter.new.import!(params[:id])
        render json: { data: result.as_json }
      rescue Gamedb::IgdbImageImporter::MissingIgdbIdError => error
        render json: { error: "missing_igdb_id", message: error.message }, status: :unprocessable_entity
      rescue Gamedb::IgdbImageImporter::MissingIgdbGameError => error
        render json: { error: "igdb_game_not_found", message: error.message }, status: :not_found
      rescue Igdb::Client::ConfigurationError => error
        render json: { error: "igdb_not_configured", message: error.message }, status: :unprocessable_entity
      rescue Igdb::Client::RequestError => error
        render json: { error: "igdb_request_failed", message: error.message }, status: :bad_gateway
      rescue Gamedb::GameImageStorage::InvalidImageError => error
        render json: { error: "image_import_failed", message: error.message }, status: :unprocessable_entity
      rescue Backblaze::Client::ConfigurationError => error
        render json: { error: "backblaze_not_configured", message: error.message }, status: :unprocessable_entity
      rescue Backblaze::Client::RequestError => error
        render json: { error: "backblaze_request_failed", message: error.message }, status: :bad_gateway
      end

      def releases
        render json: { data: releases_for(GamedbGame.find(params[:id])) }
      end

      def relations
        game = GamedbGame.find(params[:id])
        render json: {
          data: {
            platforms: game.platforms.order(:platform_name).as_json,
            releases: releases_for(game),
            companies: companies_for(game),
            franchises: game.franchises.order(:name).as_json,
            genres: game.genres.order(:name).as_json,
            modes: game.modes.order(:name).as_json,
            perspectives: game.perspectives.order(:name).as_json,
            themes: game.themes.order(:name).as_json,
            alternates: game.alternate_games.as_json
          }
        }
      end

      private

      def apply_winner_filter(scope)
        case params[:winner]
        when "gotm" then scope.gotm_winners
        when "nr_gotm" then scope.nr_gotm_winners
        when "any" then scope.any_winners
        else scope
        end
      end

      def releases_for(game)
        game
          .releases
          .includes(:platform, :region)
          .sort_by { |release| [ release.release_date || Date.new(9999, 12, 31), release.platform.platform_name, release.region.region_name ] }
          .map { |release| release_json(release) }
      end

      def release_json(release)
        release.as_json.merge(
          "platform_code" => release.platform.platform_code,
          "platform_name" => release.platform.platform_name,
          "region_code" => release.region.region_code,
          "region_name" => release.region.region_name
        )
      end

      def companies_for(game)
        game.game_companies.includes(:company).sort_by { |game_company| game_company.company.name.to_s }.map do |game_company|
          game_company.company.as_json.merge("role" => game_company.role)
        end
      end

      def limit
        [ [ params.fetch(:limit, 25).to_i, 1 ].max, 100 ].min
      end

      def offset
        [ params.fetch(:offset, 0).to_i, 0 ].max
      end
    end
  end
end
