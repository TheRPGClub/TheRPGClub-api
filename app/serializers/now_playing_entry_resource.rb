# frozen_string_literal: true

# A UserNowPlaying entry with its embedded game and platform, for the user's own
# now-playing list. The consumer-audited column set + journal aggregates live in
# NowPlayingFields (#36, #104); the `game`/`platform` embeds (with the bot's
# extra `linked_thread_id` / `platform_abbreviation`) live in NowPlayingEmbeds.
# Each embed renders `null` when the entry has no game / platform.
#
# Records should be loaded through `UserNowPlaying.with_now_playing_details` so
# the journal and linked-thread fields are populated.
class NowPlayingEntryResource
  include BaseResource
  include NowPlayingFields
  include NowPlayingEmbeds
end
