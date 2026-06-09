# frozen_string_literal: true

# A UserGameReview with its embedded game. Replaces the legacy
# `serialize_with_game` helper for the reviews preview on a user's profile: all
# review columns plus `game`.
class ReviewEntryResource
  include BaseResource

  columns_of UserGameReview
  one :game, resource: GameSummaryResource
end
