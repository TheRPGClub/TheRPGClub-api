# frozen_string_literal: true

# What the review and revision endpoints share: who may read a Draft, and how
# a saved (or refused) take is rendered (spec api#430).
module ReviewTakeResponses
  extend ActiveSupport::Concern

  # The refusals a take's save can meet, by the model error detail on
  # `rating` or `review`: 422 with the detail as the `error` code.
  REFUSALS = {
    rating_required: "A score is required to publish.",
    score_locked: "A score can't change more than 7 days after it was published; publish a Revision instead.",
    review_not_published: "Only a Published Review can be Revisited.",
    draft_revision_exists: "This Review already has a Draft Revision."
  }.freeze

  private

  # Renders the saved take, or the refusal: 422 with a REFUSALS code
  # (`rating_required`, `score_locked` per ADR 0013, ...), otherwise the
  # usual validation message.
  def render_saved(record, saved, status: :ok)
    return render(json: { data: take_json(record) }, status: status) if saved

    code, message = REFUSALS.find do |detail, _|
      record.errors.added?(:rating, detail) || record.errors.added?(:review, detail)
    end
    raise ActiveRecord::RecordInvalid, record unless code

    render json: { error: code.to_s, message: message }, status: :unprocessable_content
  end

  # A Draft (a Review or a Revision) is readable only by its author and
  # Admins signed in with Discord; the service principal no longer sees one.
  def reads_drafts_of?(user_id)
    return false unless current_principal&.discord_user?

    current_principal.id.to_s == user_id.to_s || admin_or_above?
  end
end
