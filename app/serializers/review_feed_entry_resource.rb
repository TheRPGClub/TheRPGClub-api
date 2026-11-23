# frozen_string_literal: true

# One entry of the Review Feed (`GET /api/v1/reviews`, spec api#430): a
# Published Review or a Published Revision (`kind`), a row of
# `UserGameReview.takes(:published)`, with its author and game. Still a
# superset of the Latest Reviews Dashboard Panel's shape, but `rating` is the
# take's own score, not the Review's current one.
class ReviewFeedEntryResource
  include BaseResource
  include ReviewTakeFields

  # Whether the body holds any text: false for a score-only quick take.
  # Selected by `UserGameReview.with_written`.
  attribute(:written) { |review| review.written }

  one :user, resource: UserSummaryResource
  # The game with its GOTM / NR-GOTM track flags and the months they were won.
  one :game, resource: TrackedGameResource, source: proc { tracked_game }
end
