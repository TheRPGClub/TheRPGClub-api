# frozen_string_literal: true

# A UserNowPlaying entry with its embedded game and platform. Replaces the
# legacy `serialize_with_game_and_platform` helper. `platform` renders `null`
# when the entry has no platform.
class NowPlayingEntryResource
  include BaseResource

  columns_of UserNowPlaying
  one :game, resource: GameSummaryResource
  one :platform, resource: PlatformResource
end
