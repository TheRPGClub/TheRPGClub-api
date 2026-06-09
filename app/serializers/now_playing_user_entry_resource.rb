# frozen_string_literal: true

# A UserNowPlaying entry with its embedded user, for the game-scoped now-playing
# list. Replaces the ad-hoc `entry.as_json.merge("user" => ...)`: all entry
# columns plus the `user` summary (without binary image blobs).
class NowPlayingUserEntryResource
  include BaseResource

  columns_of UserNowPlaying
  one :user, resource: UserSummaryResource
end
