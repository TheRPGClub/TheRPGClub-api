# frozen_string_literal: true

# The Edit rules of ADR 0013 for a Published take (a Review, and Revisions
# once they exist). The includer has `rating`, `published_at` and
# `edited_at` columns and defines `published?`.
#
# - The score locks 7 days after the take was published: an Edit that
#   changes it after that is refused (`score_locked` on `rating`). Title,
#   text and scorecard stay editable forever.
# - An Edit more than an hour after publishing records when it was made in
#   `edited_at`. No edit history is kept.
#
# Drafts are untouched by both: their score changes freely, and publishing
# is not an Edit.
module EditRules
  extend ActiveSupport::Concern

  SCORE_LOCK_PERIOD = 7.days
  EDITED_GRACE = 1.hour
  # The columns an Edit changes. A save that changes none of them (say the
  # editor resending what is already stored) is not an Edit.
  EDITABLE_ATTRS = %w[rating title body facets].freeze

  included do
    validate :score_unlocked
    before_save :mark_edited
  end

  # When the score stops being editable, or nil while a Draft. Served so the
  # website can show the score as locked before the member tries.
  def score_locks_at
    published_at_in_database && (published_at_in_database + SCORE_LOCK_PERIOD)
  end

  def score_locked?
    score_locks_at.present? && Time.current > score_locks_at
  end

  def serializable_hash(options = nil)
    super.merge("score_locks_at" => score_locks_at)
  end

  private

  # An Edit happens only to a take that was already Published before this
  # save; the save that publishes a Draft is not one.
  def editing_published_take?
    persisted? && published_at_in_database.present?
  end

  def score_unlocked
    return unless editing_published_take? && will_save_change_to_rating? && score_locked?

    errors.add(:rating, :score_locked,
      message: "can't change more than #{SCORE_LOCK_PERIOD.inspect} after publishing")
  end

  def mark_edited
    return unless editing_published_take?
    return unless EDITABLE_ATTRS.any? { |attr| will_save_change_to_attribute?(attr) }
    return unless Time.current > published_at_in_database + EDITED_GRACE

    self.edited_at = Time.current
  end
end
