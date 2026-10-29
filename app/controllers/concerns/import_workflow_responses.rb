# frozen_string_literal: true

# Shared responses for the server-side import workflow endpoints (web-parity
# #289-#291): the error envelope for workflow failures and the "review"
# payload that `advance` / `remap` return.
#
#   render_workflow_error("item_not_pending")
#   # => 422 { error: "item_not_pending", message: "This import item is no longer pending." }
module ImportWorkflowResponses
  extend ActiveSupport::Concern

  WORKFLOW_ERRORS = {
    "import_not_active" => [ :unprocessable_entity, "This import is not active." ],
    "item_not_pending" => [ :unprocessable_entity, "This import item is no longer pending." ],
    "game_not_found" => [ :not_found, "No GameDB game has that id." ],
    "invalid_igdb_id" => [ :unprocessable_entity, "igdb_id must be a positive integer." ],
    "igdb_game_not_found" => [ :not_found, "IGDB has no game with that id." ],
    "igdb_not_configured" => [ :unprocessable_entity, "IGDB is not configured." ],
    "igdb_request_failed" => [ :bad_gateway, "The IGDB request failed." ]
  }.freeze

  private

  def render_workflow_error(code, message = nil)
    status, default_message = WORKFLOW_ERRORS.fetch(code)
    render json: { error: code, message: message || default_message }, status: status
  end

  # { import, item|null, candidates, match_confidence, auto_applied, counts }
  # for an Imports::*Workflow::Review.
  def import_review_payload(import, review, counts, import_resource:, item_resource:)
    {
      import: import_resource.new(import).serializable_hash,
      item: review.item && item_resource.new(review.item).serializable_hash,
      candidates: Imports::CandidatePresenter.as_json(review.candidates),
      match_confidence: review.match_confidence,
      auto_applied: review.auto_applied,
      counts: counts
    }
  end
end
