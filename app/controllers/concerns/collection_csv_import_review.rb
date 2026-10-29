# frozen_string_literal: true

# Builds the collection CSV import "review" payload (#290) shared by
# collection_csv_imports#advance and collection_csv_import_items#remap:
#
#   { import, item | null, candidates: [{game_id, title, cover_url}],
#     match_confidence, counts: {import_id, by_status, by_result_reason} }
#
# Build it inside the TestModeRollback block, so a test-mode response still
# reflects the writes it rolls back.
module CollectionCsvImportReview
  extend ActiveSupport::Concern

  private

  def collection_csv_review_payload(import, item:, candidates:, match_confidence:)
    {
      import: CollectionCsvImportResource.new(import).serializable_hash,
      item: item && CollectionCsvImportItemResource.new(item).serializable_hash,
      candidates: import_candidates_json(candidates),
      match_confidence: match_confidence,
      counts: {
        import_id: import.import_id,
        by_status: import.items.group(:status).count,
        by_result_reason: import.items.group(:result_reason).count
      }
    }
  end

  # Candidates in their ranked order, with each game's primary cover.
  def import_candidates_json(candidates)
    games = GamedbGame.where(game_id: candidates.map(&:game_id)).includes(:images).index_by(&:game_id)
    candidates.map do |candidate|
      { game_id: candidate.game_id, title: candidate.title, cover_url: games[candidate.game_id]&.cover_url }
    end
  end
end
