# frozen_string_literal: true

module Api
  module V1
    # Per-row items of a RpgClubCollectionCsvImport (#163): the raw parsed CSV
    # fields plus the resolved match and outcome once the bot's matcher has run
    # a row. Owner-only, resolved through the parent import.
    class CollectionCsvImportItemsController < ApplicationController
      include TestModeRollback
      include CollectionCsvImportReview

      before_action :require_owner!, only: %i[next_pending show apply_selection skip remap igdb_candidates]
      # Item results are written by the bot (service) only.
      before_action :require_service!, only: %i[update]

      UPDATE_ATTRS = %w[status match_confidence match_candidate_json gamedb_game_id collection_entry_id result_reason error_text].freeze

      # HTTP status per Imports::IgdbGameResolver error code.
      IGDB_ERROR_STATUS = {
        "invalid_igdb_id" => :unprocessable_content,
        "igdb_not_configured" => :unprocessable_content,
        "igdb_game_not_found" => :not_found,
        "igdb_request_failed" => :bad_gateway
      }.freeze

      # GET /api/v1/collection_csv_imports/:id/items/next_pending
      #
      # The next pending item ordered by row_index, or null once every row has
      # been processed.
      def next_pending
        import = RpgClubCollectionCsvImport.find(params[:id])
        record = import.items.where(status: "pending").order(:row_index).first

        render json: { data: record && CollectionCsvImportItemResource.new(record).serializable_hash }
      end

      # GET /api/v1/collection_csv_import_items/:id
      def show
        record = RpgClubCollectionCsvImportItem.find(params[:id])
        render json: { data: CollectionCsvImportItemResource.new(record).serializable_hash }
      end

      # PATCH /api/v1/collection_csv_import_items/:id
      # Body: { "data": { status, match_confidence, match_candidate_json,
      #                    gamedb_game_id, collection_entry_id, result_reason, error_text } }
      def update
        record = RpgClubCollectionCsvImportItem.find(params[:id])
        with_test_mode_rollback(record.import.test_mode) { record.update!(request_data.slice(*UPDATE_ATTRS)) }
        render json: { data: CollectionCsvImportItemResource.new(record).serializable_hash }
      end

      # POST /api/v1/collection_csv_import_items/:id/apply
      # Body: { "data": { game_id } } or { "data": { igdb_id } }
      #
      # Adds the chosen game to the owner's collection with the row's
      # platform, ownership and note (reason manual_remap). An `igdb_id` is
      # imported into GameDB first (owner-safe; never the admin POST /games)
      # and stored as the item's only candidate. A duplicate collection entry
      # marks the item skipped/duplicate. Returns the updated item.
      def apply_selection
        item = RpgClubCollectionCsvImportItem.find(params[:id])
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
          Imports::CollectionCsvWorkflow.new(item.import).apply(item, game, reason: "manual_remap")
        end
        return render json: { error: error }, status: error_status(error) if error

        render json: { data: CollectionCsvImportItemResource.new(item).serializable_hash }
      end

      # POST /api/v1/collection_csv_import_items/:id/skip
      #
      # Marks the row skipped/manual_skip. Returns the updated item.
      def skip
        item = RpgClubCollectionCsvImportItem.find(params[:id])
        return unless actionable!(item)

        with_test_mode_rollback(item.import.test_mode) { Imports::CollectionCsvWorkflow.new(item.import).skip(item) }
        render json: { data: CollectionCsvImportItemResource.new(item).serializable_hash }
      end

      # POST /api/v1/collection_csv_import_items/:id/remap
      # Body: { "data": { title } }
      #
      # Searches GameDB for a different title and stores the candidates on the
      # row (result_reason no_candidate when there are none). Returns the same
      # review payload as collection_csv_imports#advance. A single candidate
      # that exactly matches the row's raw_title is auto-applied by the next
      # advance.
      def remap
        item = RpgClubCollectionCsvImportItem.find(params[:id])
        return unless actionable!(item)

        title = request_data["title"].to_s.strip
        return render json: { error: "title_required" }, status: :unprocessable_content if title.empty?

        import = item.import
        payload = with_test_mode_rollback(import.test_mode) do
          candidates = Imports::CollectionCsvWorkflow.new(import).remap(item, title)
          collection_csv_review_payload(import, item: item, candidates: candidates,
            match_confidence: item.match_confidence)
        end

        render json: { data: payload }
      end

      # GET /api/v1/collection_csv_import_items/:id/igdb_candidates?q=
      #
      # IGDB suggestions for the row (Imports::IgdbCandidateSearch), searching
      # `q` or else the row's raw_title by progressive title variants. Each
      # hit carries `already_imported`. Pick one with `apply {igdb_id}`.
      def igdb_candidates
        item = RpgClubCollectionCsvImportItem.find(params[:id])
        title = params[:q].presence || item.raw_title

        render json: { data: Imports::IgdbCandidateSearch.new.search(title) }
      rescue Igdb::Client::ConfigurationError
        render json: { error: "igdb_not_configured" }, status: :unprocessable_content
      rescue Igdb::Client::RequestError
        render json: { error: "igdb_request_failed" }, status: :bad_gateway
      end

      private

      # Renders 409 and returns false unless the import is active and the
      # item still pending.
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

      def resolve_owner_id
        return RpgClubCollectionCsvImport.find_by(import_id: params[:id])&.user_id if action_name == "next_pending"
        return nil unless params[:id].present?

        RpgClubCollectionCsvImportItem.find_by(item_id: params[:id])&.import&.user_id
      end
    end
  end
end
