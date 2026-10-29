# frozen_string_literal: true

module Api
  module V1
    # Per-row items of a RpgClubCompletionatorImport (#164): the raw parsed
    # Completionator export fields plus the resolved match and outcome once
    # the bot's matcher has run a row. Owner-only, resolved through the
    # parent import.
    class CompletionatorImportItemsController < ApplicationController
      include TestModeRollback

      rescue_from Imports::CompletionatorWorkflow::Error do |error|
        render json: { error: error.code, message: error.message }, status: error.status
      end

      WORKFLOW_ACTIONS = %i[match add_completion update_completion skip].freeze
      IGDB_CANDIDATE_LIMIT = 10
      IGDB_ERROR_STATUS = {
        "invalid_igdb_id" => :unprocessable_entity,
        "igdb_not_configured" => :unprocessable_entity,
        "igdb_game_not_found" => :not_found,
        "igdb_request_failed" => :bad_gateway
      }.freeze

      before_action :require_owner!, only: %i[next_pending show igdb_candidates] + WORKFLOW_ACTIONS
      before_action :load_pending_item, only: WORKFLOW_ACTIONS
      # Item results are written by the bot (service) only.
      before_action :require_service!, only: %i[update]

      UPDATE_ATTRS = %w[status gamedb_game_id completion_id error_text].freeze

      # GET /api/v1/completionator_imports/:id/items/next_pending
      #
      # The next pending item ordered by row_index, or null once every row has
      # been processed.
      def next_pending
        import = RpgClubCompletionatorImport.find(params[:id])
        record = import.items.where(status: "pending").order(:row_index).first

        render json: { data: record && CompletionatorImportItemResource.new(record).serializable_hash }
      end

      # GET /api/v1/completionator_import_items/:id
      def show
        record = RpgClubCompletionatorImportItem.find(params[:id])
        render json: { data: CompletionatorImportItemResource.new(record).serializable_hash }
      end

      # PATCH /api/v1/completionator_import_items/:id
      # Body: { "data": { status, gamedb_game_id, completion_id, error_text } }
      def update
        record = RpgClubCompletionatorImportItem.find(params[:id])
        with_test_mode_rollback(record.import.test_mode) { record.update!(request_data.slice(*UPDATE_ATTRS)) }
        render json: { data: CompletionatorImportItemResource.new(record).serializable_hash }
      end

      # ---- workflow (#291, see Imports::CompletionatorWorkflow) -------------
      # Owner-only; only a pending item can be acted on (422
      # `item_not_pending`). Writes are rolled back if the import is in
      # test_mode. Workflow failures render 422 (404 for an unknown game)
      # as `{ error: <code>, message }`.

      # POST /api/v1/completionator_import_items/:id/match
      # Body: { "data": { game_id } } or { "data": { igdb_id } }
      #
      # Sets the item's game and returns its CompletionatorReview, applying
      # the automatic step (auto-add, auto-skip) like advance does. An
      # igdb_id not yet in GameDB is imported first (Imports::IgdbGameResolver);
      # that import is a catalog write and is kept even in test_mode.
      def match
        game = matched_game
        return if performed?

        review = workflow_write { |workflow| workflow.match(@item, game) }
        render json: { data: CompletionatorReviewPayload.new(review).as_json }
      end

      # POST /api/v1/completionator_import_items/:id/add_completion
      # Body: { "data": { completion_type, platform_id, completed_at, final_playtime_hours } }
      #
      # Adds a new completion for the matched game; omitted fields take the
      # review form's defaults, `platform_id: null` records no platform.
      # Creates the game's missing WW release when the platform is the
      # item's mapped platform. Returns the item (status `added`).
      def add_completion
        attrs = params[:data].present? ? request_data.slice(*ADD_ATTRS) : {}
        render_item(workflow_write { |workflow| workflow.add_completion(@item, attrs) })
      end
      ADD_ATTRS = %w[completion_type platform_id completed_at final_playtime_hours].freeze

      # POST /api/v1/completionator_import_items/:id/update_completion
      # Body: { "data": { fields: ["type", "date", "playtime"] } }
      #
      # Copies the selected fields from the row onto the existing completion
      # (status `updated`), or skips the item when none of them differ.
      def update_completion
        fields = params.dig(:data, :fields)
        render_item(workflow_write { |workflow| workflow.update_completion(@item, fields) })
      end

      # POST /api/v1/completionator_import_items/:id/skip
      def skip
        render_item(workflow_write { |workflow| workflow.skip(@item) })
      end

      # GET /api/v1/completionator_import_items/:id/igdb_candidates?q=
      #
      # IGDB suggestions for the row (the bot's single igdbService.searchGames
      # query, 10 results), searching `q` or the item's title. Each result is
      # flagged `already_imported` like igdb#search.
      def igdb_candidates
        item = RpgClubCompletionatorImportItem.find(params[:id])
        query = params[:q].presence || item.game_title
        results = Igdb::Client.new.search(query, limit: IGDB_CANDIDATE_LIMIT)
        imported = GamedbGame.where(igdb_id: results.map { |result| result[:igdb_id] }).pluck(:igdb_id).to_set

        render json: { data: results.map { |result| result.merge(already_imported: imported.include?(result[:igdb_id])) } }
      rescue Igdb::Client::ConfigurationError => error
        render json: { error: "igdb_not_configured", message: error.message }, status: :unprocessable_entity
      rescue Igdb::Client::RequestError => error
        render json: { error: "igdb_request_failed", message: error.message }, status: :bad_gateway
      end

      private

      def load_pending_item
        @item = RpgClubCompletionatorImportItem.find(params[:id])
        return if @item.status == "pending"

        render json: { error: "item_not_pending", message: "This item was already processed (#{@item.status})" },
          status: :unprocessable_entity
      end

      def matched_game
        data = params[:data].present? ? request_data : {}
        if data["igdb_id"].present?
          result = Imports::IgdbGameResolver.new.resolve(data["igdb_id"])
          return result.game if result.ok?

          return render(json: { error: result.error }, status: IGDB_ERROR_STATUS.fetch(result.error, :unprocessable_entity))
        end
        if data["game_id"].blank?
          return render(json: { error: "game_required", message: "Provide game_id or igdb_id" }, status: :unprocessable_entity)
        end

        GamedbGame.find_by(game_id: data["game_id"]) ||
          render(json: { error: "game_not_found", message: "GameDB game #{data['game_id']} not found" }, status: :not_found)
      end

      def workflow_write
        import = @item.import
        with_test_mode_rollback(import.test_mode) { yield Imports::CompletionatorWorkflow.new(import) }
      end

      def render_item(item)
        render json: { data: CompletionatorImportItemResource.new(item).serializable_hash }
      end

      def resolve_owner_id
        return RpgClubCompletionatorImport.find_by(import_id: params[:id])&.user_id if action_name == "next_pending"
        return nil unless params[:id].present?

        RpgClubCompletionatorImportItem.find_by(item_id: params[:id])&.import&.user_id
      end
    end
  end
end
