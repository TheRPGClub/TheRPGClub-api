# frozen_string_literal: true

# What the review and revision endpoints share: who may read a Draft, and how
# a saved (or refused) take is rendered (spec api#430).
module ReviewTakeResponses
  extend ActiveSupport::Concern

  # The refusals a take's save can meet, by the model error detail on
  # `rating` or `review`, checked in this order: 422 with the `error` code
  # and message. A locked score is reported as locked before anything else,
  # and clearing a Published take's score shares the publish code with its
  # own message.
  REFUSALS = {
    score_locked: [ "score_locked",
      "A score can't change more than 7 days after it was published; publish a Revision instead." ],
    score_kept: [ "rating_required", "A Published take must keep its score." ],
    rating_required: [ "rating_required", "A score is required to publish." ],
    review_not_published: [ "review_not_published", "Only a Published Review can be Revisited." ],
    draft_revision_exists: [ "draft_revision_exists", "This Review already has a Draft Revision." ]
  }.freeze

  private

  # Renders the saved take, or the refusal: 422 with a REFUSALS code
  # (`rating_required`, `score_locked` per ADR 0013, ...), otherwise the
  # usual validation message.
  def render_saved(record, saved, status: :ok)
    return render(json: { data: take_json(record) }, status: status) if saved

    detail = REFUSALS.keys.find do |key|
      record.errors.added?(:rating, key) || record.errors.added?(:review, key)
    end
    raise ActiveRecord::RecordInvalid, record unless detail

    render_refusal(detail)
  end

  def render_refusal(detail)
    code, message = REFUSALS.fetch(detail)
    render json: { error: code, message: message }, status: :unprocessable_content
  end

  # A Draft (a Review or a Revision) is readable only by its author and
  # Admins signed in with Discord; the service principal no longer sees one.
  def reads_drafts_of?(user_id)
    return false unless current_principal&.discord_user?

    current_principal.id.to_s == user_id.to_s || admin_or_above?
  end
end
