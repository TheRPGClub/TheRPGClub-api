# frozen_string_literal: true

# Builds the Completionator import "review" payload (#291) shared by
# completionator_imports#advance and completionator_import_items#match. It
# follows the collection CSV review (#290) and adds the Completionator
# steps:
#
#   { import, item | null, candidates: [{game_id, title, cover_url}],
#     match_confidence, counts: {import_id, by_status},
#     next_step, game, existing_completion, diff, form, auto_processed }
#
# Build it inside the TestModeRollback block, so a test-mode response still
# reflects the writes it rolls back.
module CompletionatorImportReview
  extend ActiveSupport::Concern
  include CollectionCsvImportReview

  private

  def completionator_review_payload(import, review, auto_processed: 0)
    {
      import: CompletionatorImportResource.new(import).serializable_hash,
      item: review.item && CompletionatorImportItemResource.new(review.item).serializable_hash,
      candidates: import_candidates_json(review.candidates),
      match_confidence: review.item && Imports::CandidateFinder.confidence(review.item.game_title, review.candidates),
      counts: { import_id: import.import_id, by_status: import.items.group(:status).count },
      next_step: review.next_step,
      game: review.game && GameSummaryResource.new(review.game).serializable_hash,
      existing_completion: review.existing_completion &&
        CompletionEntryResource.new(review.existing_completion).serializable_hash,
      diff: review.diff,
      form: review.form&.merge(platforms: PlatformResource.new(review.form[:platforms]).serializable_hash),
      auto_processed: auto_processed
    }
  end
end
