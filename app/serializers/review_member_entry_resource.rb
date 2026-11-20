# frozen_string_literal: true

# A UserGameReview with its author and game, for the club-wide feed
# (`GET /api/v1/reviews`), where neither is implied by the path.
class ReviewMemberEntryResource
  include BaseResource
  include ReviewFields

  one :user, resource: UserSummaryResource
  one :game, resource: GameSummaryResource
end
