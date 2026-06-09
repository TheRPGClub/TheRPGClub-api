# frozen_string_literal: true

# A UserGameReview with its embedded user, for the game-scoped reviews list.
# Replaces the ad-hoc `entry.as_json.merge("user" => ...)`: all review columns
# plus the `user` summary (without binary image blobs).
class ReviewUserEntryResource
  include BaseResource

  columns_of UserGameReview
  one :user, resource: UserSummaryResource
end
