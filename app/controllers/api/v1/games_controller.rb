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
        game = GamedbGame.without_images.includes(:images).find(params[:id])

        render json: {
          data: game_record_data(game).merge(
            "now_playing" => NowPlayingUserEntryResource.new(now_playing_for(game)).serializable_hash,
            "completions" => CompletionUserEntryResource.new(completions_for(game)).serializable_hash
          )
        }
      end

      # POST /api/v1/games  { "igdb_id": 1234 }
      #
      # Admin/service-only. Creates a game from IGDB: fetches the full payload,
      # upserts the gamedb_games row + taxonomy + releases, then imports its
      # cover/artwork/logo images into Backblaze through the same importer the
      # jobs use (#122). Idempotent on `igdb_id` — re-POSTing refreshes the
      # existing game and returns 200 instead of 201. Mirrors the IGDB/Backblaze
      # rescue ladder from #refresh_images.
      def create
        return unless require_admin_or_service!

        result = Gamedb::IgdbGameImporter.new.import!(igdb_id_param)
        # Reload through `without_images` so GameResource's gotm_won / nr_gotm_won
        # SQL aliases and per-kind image URLs resolve (see GameFields), exactly as
        # #show does.
        game = GamedbGame.without_images.includes(:images).find(result.game.game_id)

        render json: {
          data: GameResource.new(game).serializable_hash,
          images: result.images.as_json
        }, status: result.created ? :created : :ok
      rescue Gamedb::IgdbGameImporter::MissingIgdbGameError, Gamedb::IgdbImageImporter::MissingIgdbGameError => error
        render json: { error: "igdb_game_not_found", message: error.message }, status: :not_found
      rescue Gamedb::IgdbImageImporter::MissingIgdbIdError => error
        render json: { error: "missing_igdb_id", message: error.message }, status: :unprocessable_entity
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
        render json: { data: relations_data(GamedbGame.find(params[:id])) }
      end

      # GET /api/v1/games/:id/profile
      #
      # One aggregate payload for the bot's `/gamedb view` (#115): the game
      # record (same shape as #show), its relations (same shape as #relations),
      # the full now-playing / completions / threads lists, the resolved primary
      # image, and the GOTM/NR-GOTM associations, collection owners and HLTB
      # cache the bot otherwise read via direct SQL. Collapses six HTTP calls
      # plus three SQL reads into a single request.
      def profile
        # Preload images once: GameResource's cover/art/logo URLs and the
        # primary-image lookup below all read from the same set, and
        # GamedbGame#primary_image_url resolves in-memory when it's loaded —
        # collapsing four per-kind image queries into one.
        game = GamedbGame.without_images.includes(:images).find(params[:id])

        render json: {
          data: {
            game: game_record_data(game),
            relations: relations_data(game),
            # The full, unpaginated lists — preferred over a preview for a single
            # game (#115); the standalone endpoints paginate, these do not.
            now_playing: NowPlayingUserEntryResource.new(now_playing_for(game)).serializable_hash,
            completions: CompletionUserEntryResource.new(completions_for(game)).serializable_hash,
            threads: ThreadResource.new(threads_for(game)).serializable_hash,
            primary_image: primary_image_for(game),
            associations: associations_for(game),
            collection_owners: collection_owners_for(game),
            hltb: hltb_for(game)
          }
        }
      end

      private

      # The IGDB id to import, accepted top-level (`{ "igdb_id": 1234 }`). A
      # missing or non-integer value is a 400 (ActionController::ParameterMissing
      # -> render_bad_request), matching the other write endpoints.
      def igdb_id_param
        raw = params[:igdb_id].presence
        raise ActionController::ParameterMissing, :igdb_id if raw.blank?

        Integer(raw)
      rescue ArgumentError, TypeError
        raise ActionController::ParameterMissing, :igdb_id
      end

      # The game record exactly as #show renders it minus the now-playing /
      # completions previews (the profile surfaces those as dedicated top-level
      # lists instead of a redundant second copy): the GameResource shape plus
      # the GOTM / NR-GOTM month info derived from the winning entries.
      def game_record_data(game)
        GameResource.new(game).serializable_hash.merge(
          "gotm_month_year" => game.gotm_won ? game.gotm_entries.order(round_number: :desc).pick(:month_year) : nil,
          "nr_gotm_month_year" => game.nr_gotm_won ? game.nr_gotm_entries.order(round_number: :desc).pick(:month_year) : nil
        )
      end

      def relations_data(game)
        companies = game.game_companies.includes(:company).sort_by { |game_company| game_company.company.name.to_s }

        {
          platforms: PlatformResource.new(game.platforms.order(:platform_name)).serializable_hash,
          releases: releases_for(game),
          companies: GameCompanyResource.new(companies).serializable_hash,
          collection: game.collection && CollectionResource.new(game.collection).serializable_hash,
          franchises: FranchiseResource.new(game.franchises.order(:name)).serializable_hash,
          genres: GenreResource.new(game.genres.order(:name)).serializable_hash,
          engines: EngineResource.new(game.engines.order(:name)).serializable_hash,
          modes: ModeResource.new(game.modes.order(:name)).serializable_hash,
          perspectives: PerspectiveResource.new(game.perspectives.order(:name)).serializable_hash,
          themes: ThemeResource.new(game.themes.order(:name)).serializable_hash,
          alternates: GameResource.new(game.alternate_games).serializable_hash
        }
      end

      # Mirror the game-scoped now_playing / completions / threads endpoints
      # (NowPlayingController#index, CompletionsController#game_index,
      # ThreadsController#game_index) so the embedded lists match row-for-row.
      def now_playing_for(game)
        UserNowPlaying.where(gamedb_game_id: game.game_id).includes(:user).order(added_at: :desc)
      end

      def completions_for(game)
        UserGameCompletion.where(gamedb_game_id: game.game_id).includes(:user).order(completed_at: :desc)
      end

      def threads_for(game)
        DiscordThread
          .joins(:thread_game_links)
          .where(thread_game_links: { gamedb_game_id: game.game_id })
          .order(created_at: :desc)
      end

      # The single resolved primary image (the head of the same `primary_first`
      # ordering GameImagesController#index returns), as `{ url }`; nil when the
      # game has no images. Resolved in-memory off the preloaded `images` so it
      # adds no query.
      def primary_image_for(game)
        image = game.images.min_by { |img| [ img.is_primary ? 0 : 1, img.position.to_i, img.image_id.to_i ] }
        image && { url: image.url }
      end

      # GOTM / NR-GOTM wins (the rounds the game won) and nominations (the rounds
      # it was nominated for, with the nominator), currently SQL-only on the bot.
      def associations_for(game)
        {
          gotm_wins: GotmWinResource.new(game.gotm_entries.order(:round_number)).serializable_hash,
          nr_gotm_wins: GotmWinResource.new(game.nr_gotm_entries.order(:round_number)).serializable_hash,
          gotm_nominations: GotmNominationSummaryResource.new(
            game.gotm_nominations.includes(:user).order(:round_number)
          ).serializable_hash,
          nr_gotm_nominations: GotmNominationSummaryResource.new(
            game.nr_gotm_nominations.includes(:user).order(:round_number)
          ).serializable_hash
        }
      end

      # The members who own this game, deduped by user (a member may own it on
      # several platforms) and ordered by name for a stable display.
      def collection_owners_for(game)
        owners = game.user_game_collections
          .includes(:user)
          .to_a
          .uniq(&:user_id)
          .sort_by { |entry| [ entry.user&.username.to_s.downcase, entry.user_id.to_s ] }
        CollectionOwnerResource.new(owners).serializable_hash
      end

      # The scraped HLTB cache row, or nil when none exists.
      def hltb_for(game)
        cache = game.hltb_cache
        cache && HltbResource.new(cache).serializable_hash
      end

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
