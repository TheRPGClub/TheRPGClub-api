# frozen_string_literal: true

# Builds the Steam import "review" payload (#289) shared by
# steam_collection_imports#advance and steam_collection_import_items#remap,
# in the same shape as CollectionCsvImportReview:
#
#   { import, item | null, candidates: [{game_id, title, cover_url}],
#     match_confidence, counts: {import_id, by_status, by_result_reason} }
#
# Build it inside the TestModeRollback block, so a test-mode response still
# reflects the writes it rolls back.
module SteamCollectionImportReview
  extend ActiveSupport::Concern
  include ImportCandidatesJson

  private

  def steam_review_payload(import, item:, candidates:, match_confidence:)
    {
      import: SteamCollectionImportResource.new(import).serializable_hash,
      item: item && SteamCollectionImportItemResource.new(item).serializable_hash,
      candidates: import_candidates_json(candidates),
      match_confidence: match_confidence,
      counts: {
        import_id: import.import_id,
        by_status: import.items.group(:status).count,
        by_result_reason: import.items.group(:result_reason).count
      }
    }
  end
end
