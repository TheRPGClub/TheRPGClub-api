# frozen_string_literal: true

module Api
  module V1
    # Per-row items of a RpgClubCompletionatorImport (#164): the raw parsed
    # Completionator export fields plus the resolved match and outcome once
    # the bot's matcher has run a row. Owner-only, resolved through the
    # parent import.
    class CompletionatorImportItemsController < ApplicationController
      include TestModeRollback
      include CompletionatorImportReview
      include ImportItemActions

      rescue_from Imports::CompletionatorWorkflow::Error do |error|
        render json: { error: error.code, message: error.message }, status: :unprocessable_content
      end

      WORKFLOW_ACTIONS = %i[match add_completion update_completion skip].freeze

      before_action :require_owner!, only: %i[next_pending show igdb_candidates] + WORKFLOW_ACTIONS
      # GET .../:id/igdb_candidates (shared with the collection CSV import)
      # searches `q` or else the item's game_title; pick a hit with
      # `match {igdb_id}`.
      import_item_actions RpgClubCompletionatorImportItem, title: :game_title, actionable: WORKFLOW_ACTIONS
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
      # Owner-only; only a pending item of an active import can be acted on
      # (409 `item_not_pending` / `import_not_active`, as for the collection
      # CSV items). Writes are rolled back if the import is in test_mode.
      # Workflow failures render 422 `{ error: <code>, message }`.

      # POST /api/v1/completionator_import_items/:id/match
      # Body: { "data": { game_id } } or { "data": { igdb_id } }
      #
      # Sets the item's game and returns the same review payload as advance
      # (CompletionatorImportReview), applying the automatic step (auto-add,
      # auto-skip; `next_step` auto_added / auto_skipped). An
      # igdb_id not yet in GameDB is imported first (Imports::IgdbGameResolver),
      # inside the test-mode rollback like the collection CSV and Steam apply.
      def match
        game_id, igdb_id = game_choice(params[:data].present? ? request_data : {})
        return if performed?

        import = @item.import
        error = nil
        payload = with_test_mode_rollback(import.test_mode) do
          game, error = chosen_game(game_id, igdb_id)
          next unless game

          @item.lock!
          completionator_review_payload(import, Imports::CompletionatorWorkflow.new(import).match(@item, game))
        end
        return render_game_error(error) if error

        render json: { data: payload }
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

      private

      def workflow_write
        import = @item.import
        with_test_mode_rollback(import.test_mode) do
          @item.lock!
          yield Imports::CompletionatorWorkflow.new(import)
        end
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
