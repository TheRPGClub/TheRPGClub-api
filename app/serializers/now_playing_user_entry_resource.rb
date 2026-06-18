# frozen_string_literal: true

# A UserNowPlaying entry with its embedded user, for the game-scoped now-playing
# list: the consumer-audited NowPlayingFields columns + journal aggregates (#104)
# plus the `user` summary (without binary image blobs). The game is implied by
# the path, so no game/platform embed is included.
#
# Records should be loaded through `UserNowPlaying.with_now_playing_details` so
# the journal fields are populated.
class NowPlayingUserEntryResource
  include BaseResource
  include NowPlayingFields

  one :user, resource: UserSummaryResource
end
