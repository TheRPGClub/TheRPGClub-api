# frozen_string_literal: true

# One entry of the Review Feed (`GET /api/v1/reviews`, spec api#430): a
# Published Review with its author and game, plus what a feed box needs.
# Still a superset of the Latest Reviews Dashboard Panel's shape.
#
# `kind` is "review" for every entry until Revisions join the feed as their
# own entries (then "revision", with `revision_id` and `previous_rating`).
class ReviewFeedEntryResource
  include BaseResource
  include ReviewFields

  attribute(:kind) { |_review| "review" }
  attribute(:revision_id) { |_review| nil }
  attribute(:previous_rating) { |_review| nil }
  # Whether the body holds any text: false for a score-only quick take.
  # Selected by `UserGameReview.with_written`.
  attribute(:written) { |review| review.written }

  one :user, resource: UserSummaryResource
  # Carries the GOTM / NR-GOTM track flags; the controller passes
  # GameTrackSummaryResource.params_for the page's games.
  one :game, resource: GameTrackSummaryResource
end
