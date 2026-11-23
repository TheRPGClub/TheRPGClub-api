# frozen_string_literal: true

# A Revision (spec api#430, ticket #433): a dated return to a Published
# Review, such as after a second playthrough, with its own score, optional
# written take and optional scorecard. It is a Draft until its author
# publishes it, and publishing needs a score. The latest Published Revision's
# score is its Review's current score, so deleting one restores the score
# before it. A Review has at most one Draft Revision at a time, and only a
# Published Review can be Revisited.
class UserGameReviewRevision < ApplicationRecord
  self.table_name = "user_game_review_revisions"
  self.primary_key = "revision_id"

  # The 7-day score lock and the edited marker (ADR 0013), each counted from
  # this Revision's own publish date.
  include EditRules
  # The score, title and scorecard every take shares, with their validation.
  include ReviewTake

  belongs_to :review, class_name: "UserGameReview", inverse_of: :revisions

  validate :review_published, on: :create
  validate :one_draft_per_review, on: :create

  # The score this take replaced: for a Published Revision, the score just
  # before it was published; for a Draft, the Review's current score. A
  # Review's revision history sets it in bulk (UserGameReview#revision_history)
  # rather than one query per Revision.
  attr_writer :previous_rating

  def previous_rating
    return @previous_rating if defined?(@previous_rating)

    earlier = review.revisions.published.where.not(revision_id: revision_id)
    if published?
      earlier = earlier.where("(published_at, revision_id) < (?, ?)", published_at, revision_id)
    end
    @previous_rating = earlier.order(published_at: :desc, revision_id: :desc).pick(:rating) || review.rating
  end

  def serializable_hash(options = nil)
    super.merge("previous_rating" => previous_rating)
  end

  private

  def review_published
    return if review.nil? || review.published?

    errors.add(:review, :review_not_published, message: "must be Published before it can be Revisited")
  end

  def one_draft_per_review
    return if published? || review.nil?
    return unless review.revisions.drafts.exists?

    errors.add(:review, :draft_revision_exists, message: "already has a Draft Revision")
  end
end
