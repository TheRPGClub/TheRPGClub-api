# frozen_string_literal: true

# A UserNowPlaying entry with its owning user *and* embedded game/platform, for
# the cross-member endpoints (the all-members list `GET /api/v1/now_playing`,
# single-entry `GET /api/v1/now_playing/:id` and `PATCH`). Unlike the
# user-scoped list the member is not implied by the path, so the `user` summary
# is embedded for the bot's service/admin views (#104).
#
# Records should be loaded through `UserNowPlaying.with_now_playing_details` so
# the journal and linked-thread fields are populated.
class NowPlayingMemberEntryResource
  include BaseResource
  include NowPlayingFields
  include NowPlayingEmbeds

  one :user, resource: UserSummaryResource
end
