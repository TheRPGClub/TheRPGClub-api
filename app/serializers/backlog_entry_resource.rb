# frozen_string_literal: true

# A UserGameBacklog with its embedded game and platform. Replaces the legacy
# `serialize_with_game_and_platform` helper. `platform` renders `null` when the
# entry has no platform.
class BacklogEntryResource
  include BaseResource

  columns_of UserGameBacklog
  one :game, resource: GameSummaryResource
  one :platform, resource: PlatformResource
end
