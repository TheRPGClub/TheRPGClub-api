# frozen_string_literal: true

# One take, a Review or a Revision, as a row of `UserGameReview.takes`: the
# Review Feed's entries and the drafts listing's (spec api#430). `rating` is
# the take's own score, and a Revision carries `revision_id` and the score it
# replaced (`previous_rating`); both are null on a review.
module ReviewTakeFields
  extend ActiveSupport::Concern

  included do
    attributes :kind, :review_id, :revision_id, :user_id, :gamedb_game_id, :rating, :previous_rating, :title,
      :body, :facets, :created_at, :published_at, :edited_at
  end
end
