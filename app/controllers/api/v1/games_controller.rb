# frozen_string_literal: true

module Api
  module V1
    class GamesController < ApplicationController
      def index
        scope = params[:q].present? ? GamedbGame.search(params[:q]) : GamedbGame.without_images.order(:title)
        scope = apply_winner_filter(scope)
        scope = apply_taxonomy_filters(scope)
        # The scope carries computed SELECT columns and (for search) a custom
        # ORDER; strip both so the COUNT(*) is plain, then hand it to pagy.
        count = scope.except(:select, :order).count(:all)
        pagy, records = pagy(scope.preload(:images), **pagy_options(default_per: 25, max_per: 100).merge(count:))

        render json: {
          data: GameResource.new(records).serializable_hash,
          meta: pagy_meta(pagy).merge(resource: "gamedb_games")
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
          data: GameResource.new(game).serializable_hash.merge(
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
        companies = game.game_companies.includes(:company).sort_by { |game_company| game_company.company.name.to_s }

        render json: {
          data: {
            platforms: PlatformResource.new(game.platforms.order(:platform_name)).serializable_hash,
            releases: releases_for(game),
            companies: GameCompanyResource.new(companies).serializable_hash,
            franchises: FranchiseResource.new(game.franchises.order(:name)).serializable_hash,
            genres: GenreResource.new(game.genres.order(:name)).serializable_hash,
            engines: EngineResource.new(game.engines.order(:name)).serializable_hash,
            modes: ModeResource.new(game.modes.order(:name)).serializable_hash,
            perspectives: PerspectiveResource.new(game.perspectives.order(:name)).serializable_hash,
            themes: ThemeResource.new(game.themes.order(:name)).serializable_hash,
            alternates: GameResource.new(game.alternate_games).serializable_hash
          }
        }
      end

      private

      # Each param maps to the join model whose own FK column shares the param's
      # name (e.g. genre_id -> GamedbGameGenre#genre_id).
      TAXONOMY_FILTERS = {
        genre_id: GamedbGameGenre,
        engine_id: GamedbGameEngine,
        theme_id: GamedbGameTheme,
        perspective_id: GamedbGamePerspective,
        mode_id: GamedbGameMode,
        franchise_id: GamedbGameFranchise,
        company_id: GamedbGameCompany
      }.freeze

      def apply_winner_filter(scope)
        case params[:winner]
        when "gotm" then scope.gotm_winners
        when "nr_gotm" then scope.nr_gotm_winners
        when "any" then scope.any_winners
        else scope
        end
      end

      # Filter via `game_id IN (SELECT game_id FROM <join> WHERE <fk> = ?)` per
      # present param. AND across dimensions (chained WHEREs), and array values
      # (`?genre_id[]=1&genre_id[]=2`) become an `IN (1,2)` within a dimension —
      # both for free via AR, with no joins/`.distinct` to skew `meta.total`.
      def apply_taxonomy_filters(scope)
        TAXONOMY_FILTERS.each do |param, join_model|
          next if params[param].blank?

          scope = scope.where(game_id: join_model.where(param => params[param]).select(:game_id))
        end
        scope
      end

      def releases_for(game)
        releases = game
          .releases
          .includes(:platform, :region)
          .sort_by { |release| [ release.release_date || Date.new(9999, 12, 31), release.platform.platform_name, release.region.region_name ] }
        ReleaseResource.new(releases).serializable_hash
      end
    end
  end
end
