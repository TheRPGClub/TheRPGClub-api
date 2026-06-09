# frozen_string_literal: true

# A UserGameCompletion with its embedded user, for the game-scoped completions
# list. Replaces the ad-hoc `entry.as_json.merge("user" => ...)`: all entry
# columns plus the `user` summary (without binary image blobs).
class CompletionUserEntryResource
  include BaseResource

  columns_of UserGameCompletion
  one :user, resource: UserSummaryResource
end
