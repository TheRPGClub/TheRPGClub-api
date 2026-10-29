# frozen_string_literal: true

module Api
  module V1
    # Per-app items of a RpgClubSteamCollectionImport (#166): the raw Steam
    # app/playtime fields plus the resolved match and outcome once the bot's
    # matcher has run an app. Owner-only, resolved through the parent import.
    class SteamCollectionImportItemsController < ApplicationController
      include TestModeRollback
      include ImportWorkflowResponses

      before_action :require_owner!, only: %i[create next_pending counts show apply skip remap igdb_candidates]
      # Item results are written by the bot (service) only.
      before_action :require_service!, only: %i[update]

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
      # skipped/duplicate, or failed/add_failed). Rolled back in test_mode.
      def apply
        data = request_data
        raise ActionController::ParameterMissing, "game_id or igdb_id" if data["game_id"].blank? && data["igdb_id"].blank?

        workflow_action { |item, workflow| apply_game(item, workflow, data) }
      end

      # POST /api/v1/steam_collection_import_items/:id/skip
      #
      # Marks the item skipped (manual_skip) and records the Steam app as
      # skipped in the shared app map, so future imports flag it skip_mapped.
      def skip
        workflow_action do |item, workflow|
          workflow.skip(item)
          nil
        end
      end

      # POST /api/v1/steam_collection_import_items/:id/remap
      # Body: { "data": { title } }
      #
      # Re-searches GameDB under another title and persists the candidates
      # (no_candidate when nothing matches, invalid_remap for a blank title).
      # Returns the same review payload as advance; the next advance may
      # auto-apply a single exact match.
      def remap
        title = request_data["title"]
        payload = nil
        workflow_action(render_item: false) do |item, workflow|
          review = workflow.remap(item, title)
          payload = import_review_payload(item.import, review, workflow.counts,
            import_resource: SteamCollectionImportResource, item_resource: SteamCollectionImportItemResource)
          nil
        end
        render json: { data: payload } if payload
      end

      # GET /api/v1/steam_collection_import_items/:id/igdb_candidates?q=
      #
      # Owner-scoped IGDB suggestions for the item (`q` defaults to the Steam
      # app name), searched by progressive title variants and tagged with
      # `already_imported`.
      def igdb_candidates
        item = RpgClubSteamCollectionImportItem.find(params[:id])
        query = params[:q].presence || item.steam_app_name

        render json: { data: Imports::IgdbCandidateFinder.new.find(query) }
      rescue Igdb::Client::ConfigurationError => error
        render_workflow_error("igdb_not_configured", error.message)
      rescue Igdb::Client::RequestError
        render_workflow_error("igdb_request_failed")
      end

      private

      # Runs a workflow write on a pending item of an active import, inside
      # TestModeRollback with the item row locked. The block returns nil on
      # success or a workflow error code. Renders the item unless told not to.
      def workflow_action(render_item: true)
        item = RpgClubSteamCollectionImportItem.find(params[:id])
        import = item.import
        return render_workflow_error("import_not_active") unless import.status == "active"

        error = with_test_mode_rollback(import.test_mode) do
          item.lock!
          next "item_not_pending" unless item.status == "pending"

          yield item, Imports::SteamWorkflow.new(import)
        end
        return render_workflow_error(error) if error

        render json: { data: SteamCollectionImportItemResource.new(item).serializable_hash } if render_item
      end

      # nil on success, else a workflow error code.
      def apply_game(item, workflow, data)
        if data["game_id"].present?
          game_id = Integer(data["game_id"].to_s, 10, exception: false)
          return "game_not_found" unless game_id && GamedbGame.exists?(game_id: game_id)
        else
          result = Imports::IgdbGameResolver.new.resolve(data["igdb_id"])
          return result.error unless result.ok?

          game_id = result.game.game_id
        end
        workflow.apply(item, game_id)
        nil
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
        when "show", "update", "apply", "skip", "remap", "igdb_candidates"
          RpgClubSteamCollectionImportItem.find_by(item_id: params[:id])&.import&.user_id
        end
      end
    end
  end
end
