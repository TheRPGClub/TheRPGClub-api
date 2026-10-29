# frozen_string_literal: true

module Api
  module V1
    # Per-app items of a RpgClubSteamCollectionImport (#166): the raw Steam
    # app/playtime fields plus the resolved match and outcome once the bot's
    # matcher has run an app. Owner-only, resolved through the parent import.
    class SteamCollectionImportItemsController < ApplicationController
      include TestModeRollback
      include SteamCollectionImportReview

      before_action :require_owner!, only: %i[create next_pending counts show apply_selection skip remap igdb_candidates]
      # Item results are written by the bot (service) only.
      before_action :require_service!, only: %i[update]

      UPDATE_ATTRS = %w[status match_confidence match_candidate_json gamedb_game_id collection_entry_id result_reason error_text].freeze

      # The same codes and statuses as the collection CSV workflow (#290).
      IGDB_ERROR_STATUS = {
        "invalid_igdb_id" => :unprocessable_content,
        "igdb_not_configured" => :unprocessable_content,
        "igdb_game_not_found" => :not_found,
        "igdb_request_failed" => :bad_gateway
      }.freeze

      # POST /api/v1/steam_collection_imports/:id/items
      # Body: { "data": { items: [...] } }
      #
      # Bulk-inserts pending items for the import. Rolled back along with
      # the updated total_count if the import is in test_mode.
      def create
        import = RpgClubSteamCollectionImport.find(params[:id])
        items = Array(request_data["items"])

        with_test_mode_rollback(import.test_mode) do
          rows = items.each_with_index.map { |item, index| item_row(import.import_id, item, index) }
          RpgClubSteamCollectionImportItem.insert_all(rows) if rows.any?
          import.update!(total_count: import.total_count + rows.size)
        end

        render json: { data: SteamCollectionImportResource.new(import).serializable_hash }, status: :created
      end

      # GET /api/v1/steam_collection_imports/:id/items/next_pending
      #
      # The next pending item ordered by row_index, or null once every app has
      # been processed.
      def next_pending
        import = RpgClubSteamCollectionImport.find(params[:id])
        record = import.items.where(status: "pending").order(:row_index).first

        render json: { data: record && SteamCollectionImportItemResource.new(record).serializable_hash }
      end

      # GET /api/v1/steam_collection_imports/:id/items/counts
      #
      # Item counts grouped by status and by result_reason, replacing the
      # bot's countItemsByStatus/countItemsByReason.
      def counts
        import = RpgClubSteamCollectionImport.find(params[:id])

        render json: {
          data: {
            import_id: import.import_id,
            by_status: import.items.group(:status).count,
            by_result_reason: import.items.group(:result_reason).count
          }
        }
      end

      # GET /api/v1/steam_collection_import_items/:id
      def show
        record = RpgClubSteamCollectionImportItem.find(params[:id])
        render json: { data: SteamCollectionImportItemResource.new(record).serializable_hash }
      end

      # PATCH /api/v1/steam_collection_import_items/:id
      # Body: { "data": { status, match_confidence, match_candidate_json,
      #                    gamedb_game_id, collection_entry_id, result_reason, error_text } }
      def update
        record = RpgClubSteamCollectionImportItem.find(params[:id])
        with_test_mode_rollback(record.import.test_mode) { record.update!(request_data.slice(*UPDATE_ATTRS)) }
        render json: { data: SteamCollectionImportItemResource.new(record).serializable_hash }
      end

      # POST /api/v1/steam_collection_import_items/:id/apply
      # Body: { "data": { game_id } } or { "data": { igdb_id } }
      #
      # Server-side workflow action (#289): adds the game to the owner's
      # collection (Digital, Steam platform) and maps the Steam app to it. An
      # `igdb_id` is first resolved to a GameDB game, importing it from IGDB
      # when needed (Imports::IgdbGameResolver), so members never need the
      # admin-only POST /games. Returns the updated item (added, or
      # skipped/duplicate, or failed/add_failed). Exactly one of game_id /
      # igdb_id (422 game_id_or_igdb_id_required). 409 import_not_active /
      # item_not_pending. Rolled back in test_mode.
      def apply_selection
        item = RpgClubSteamCollectionImportItem.find(params[:id])
        return unless actionable!(item)

        data = request_data
        game_id, igdb_id = data.values_at("game_id", "igdb_id").map(&:presence)
        if game_id.nil? == igdb_id.nil?
          return render json: { error: "game_id_or_igdb_id_required" }, status: :unprocessable_content
        end

        error = nil
        with_test_mode_rollback(item.import.test_mode) do
          game, error = game_id ? find_game(game_id) : import_igdb_game(igdb_id)
          next unless game

          item.lock!
          item.update!(match_candidate_json: Imports::CandidateFinder.dump([ Imports::Candidate.new(game_id: game.game_id, title: game.title) ])) if igdb_id
          Imports::SteamWorkflow.new(item.import).apply(item, game.game_id, reason: "manual_remap")
        end
        return render json: { error: error }, status: error_status(error) if error

        render json: { data: SteamCollectionImportItemResource.new(item).serializable_hash }
      end

      # POST /api/v1/steam_collection_import_items/:id/skip
      #
      # Marks the item skipped (manual_skip) and records the Steam app as
      # skipped in the shared app map, so future imports flag it skip_mapped.
      def skip
        item = RpgClubSteamCollectionImportItem.find(params[:id])
        return unless actionable!(item)

        with_test_mode_rollback(item.import.test_mode) { Imports::SteamWorkflow.new(item.import).skip(item) }
        render json: { data: SteamCollectionImportItemResource.new(item).serializable_hash }
      end

      # POST /api/v1/steam_collection_import_items/:id/remap
      # Body: { "data": { title } }
      #
      # Re-searches GameDB under another title and persists the candidates
      # (no_candidate when nothing matches; 422 title_required for a blank
      # title). Returns the same review payload as advance; the next advance
      # may auto-apply a single exact match.
      def remap
        item = RpgClubSteamCollectionImportItem.find(params[:id])
        return unless actionable!(item)

        title = request_data["title"].to_s.strip
        return render json: { error: "title_required" }, status: :unprocessable_content if title.empty?

        import = item.import
        payload = with_test_mode_rollback(import.test_mode) do
          candidates = Imports::SteamWorkflow.new(import).remap(item, title)
          steam_review_payload(import, item: item, candidates: candidates, match_confidence: item.match_confidence)
        end

        render json: { data: payload }
      end

      # GET /api/v1/steam_collection_import_items/:id/igdb_candidates?q=
      #
      # Owner-scoped IGDB suggestions for the item (`q` defaults to the Steam
      # app name), searched by progressive title variants and tagged with
      # `already_imported`.
      def igdb_candidates
        item = RpgClubSteamCollectionImportItem.find(params[:id])
        title = params[:q].presence || item.steam_app_name

        render json: { data: Imports::IgdbCandidateSearch.new.search(title) }
      rescue Igdb::Client::ConfigurationError
        render json: { error: "igdb_not_configured" }, status: :unprocessable_content
      rescue Igdb::Client::RequestError
        render json: { error: "igdb_request_failed" }, status: :bad_gateway
      end

      private

      # Workflow actions need an active import and a pending item (409).
      def actionable!(item)
        error =
          if item.import.status != "active" then "import_not_active"
          elsif item.status != "pending" then "item_not_pending"
          end
        return true unless error

        render json: { error: error }, status: :conflict
        false
      end

      def find_game(raw_id)
        game_id = Integer(raw_id.to_s, 10, exception: false)
        game = game_id&.positive? && GamedbGame.find_by(game_id: game_id)
        game ? [ game, nil ] : [ nil, "game_not_found" ]
      end

      def import_igdb_game(raw_id)
        result = Imports::IgdbGameResolver.new.resolve(raw_id)
        [ result.game, result.error ]
      end

      def error_status(error)
        error == "game_not_found" ? :not_found : IGDB_ERROR_STATUS.fetch(error, :unprocessable_content)
      end

      def item_row(import_id, item, index)
        {
          import_id: import_id,
          row_index: item["row_index"] || index,
          steam_app_id: item["steam_app_id"],
          steam_app_name: item["steam_app_name"],
          playtime_forever_min: item["playtime_forever_min"],
          playtime_windows_min: item["playtime_windows_min"],
          playtime_mac_min: item["playtime_mac_min"],
          playtime_linux_min: item["playtime_linux_min"],
          playtime_deck_min: item["playtime_deck_min"],
          last_played_at: item["last_played_at"],
          status: "pending"
        }
      end

      def resolve_owner_id
        case action_name
        when "create", "next_pending", "counts"
          RpgClubSteamCollectionImport.find_by(import_id: params[:id])&.user_id
        when "show", "update", "apply_selection", "skip", "remap", "igdb_candidates"
          RpgClubSteamCollectionImportItem.find_by(item_id: params[:id])&.import&.user_id
        end
      end
    end
  end
end
