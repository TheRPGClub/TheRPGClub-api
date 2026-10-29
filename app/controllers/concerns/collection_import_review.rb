# frozen_string_literal: true

# Builds the "review" payload shared by the collection CSV (#290) and Steam
# (#289) imports: their advance action and their items' remap action.
#
#   { import, item | null, candidates: [{game_id, title, cover_url}],
#     match_confidence, counts: {import_id, by_status, by_result_reason} }
#
# Each controller names its resource classes:
#
#   include CollectionImportReview
#   import_review_resources import: SteamCollectionImportResource, item: SteamCollectionImportItemResource
#
#   collection_import_review_payload(import, Imports::Review.for(item, candidates))
#
# Build it inside the TestModeRollback block, so a test-mode response still
# reflects the writes it rolls back. `import_item_counts(import)` is the
# `counts` hash on its own (the summary / counts endpoints).
module CollectionImportReview
  extend ActiveSupport::Concern
  include ImportCandidatesJson

  class_methods do
    def import_review_resources(import:, item:)
      define_method(:import_review_resource) { import }
      define_method(:import_review_item_resource) { item }
      private :import_review_resource, :import_review_item_resource
    end
  end

  private

  def collection_import_review_payload(import, review)
    {
      import: import_review_resource.new(import).serializable_hash,
      item: review.item && import_review_item_resource.new(review.item).serializable_hash,
      candidates: import_candidates_json(review.candidates),
      match_confidence: review.match_confidence,
      counts: import_item_counts(import)
    }
  end

  def import_item_counts(import)
    {
      import_id: import.import_id,
      by_status: import.items.group(:status).count,
      by_result_reason: import.items.group(:result_reason).count
    }
  end
end
