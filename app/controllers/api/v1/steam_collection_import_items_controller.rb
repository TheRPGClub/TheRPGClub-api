# frozen_string_literal: true

module Api
  module V1
    # Per-app items of a RpgClubSteamCollectionImport (#166): the raw Steam
    # app/playtime fields plus the resolved match and outcome once the bot's
    # matcher has run an app. Owner-only, resolved through the parent import.
    class SteamCollectionImportItemsController < ApplicationController
      include TestModeRollback
      include CollectionImportReview
      include ImportItemActions

      before_action :require_owner!, only: %i[create next_pending counts show apply_selection skip remap igdb_candidates]
      # Item results are written by the bot (service) only.
      before_action :require_service!, only: %i[update]
      # GET .../:id/igdb_candidates searches `q` or else the Steam app name.
      import_review_resources import: SteamCollectionImportResource, item: SteamCollectionImportItemResource
      import_item_actions RpgClubSteamCollectionImportItem, title: :steam_app_name,
        actionable: %i[apply_selection skip remap]

      UPDATE_ATTRS = %w[status match_confidence match_candidate_json gamedb_game_id collection_entry_id result_reason error_text].freeze

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

        render json: { data: import_item_counts(import) }
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
        game_id, igdb_id = game_choice(request_data)
        return if performed?

        error = nil
        with_test_mode_rollback(@item.import.test_mode) do
          game, error = chosen_game(game_id, igdb_id)
          next unless game

          @item.lock!
          @item.update!(match_candidate_json: Imports::CandidateFinder.dump([ Imports::Candidate.new(game_id: game.game_id, title: game.title) ])) if igdb_id
          Imports::SteamWorkflow.new(@item.import).apply(@item, game, reason: "manual_remap")
        end
        return render_game_error(error) if error

        render json: { data: SteamCollectionImportItemResource.new(@item).serializable_hash }
      end

      # POST /api/v1/steam_collection_import_items/:id/skip
      #
      # Marks the item skipped (manual_skip) and records the Steam app as
      # skipped in the shared app map, so future imports flag it skip_mapped.
      def skip
        with_test_mode_rollback(@item.import.test_mode) { Imports::SteamWorkflow.new(@item.import).skip(@item) }
        render json: { data: SteamCollectionImportItemResource.new(@item).serializable_hash }
      end

      # POST /api/v1/steam_collection_import_items/:id/remap
      # Body: { "data": { title } }
      #
      # Re-searches GameDB under another title and persists the candidates
      # (no_candidate when nothing matches; 422 title_required for a blank
      # title). Returns the same review payload as advance; the next advance
      # may auto-apply a single exact match.
      def remap
        title = request_data["title"].to_s.strip
        return render json: { error: "title_required" }, status: :unprocessable_content if title.empty?

        import = @item.import
        payload = with_test_mode_rollback(import.test_mode) do
          candidates = Imports::SteamWorkflow.new(import).remap(@item, title)
          collection_import_review_payload(import, Imports::Review.for(@item, candidates))
        end

        render json: { data: payload }
      end

      private

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
