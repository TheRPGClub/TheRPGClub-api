# frozen_string_literal: true

# A UserGameCompletion with its member, game and platform, for the club-wide
# feed (`GET /api/v1/completions/recent`), where the member is not implied by
# the path. `platform` renders `null` when the entry has no platform.
class CompletionMemberEntryResource
  include BaseResource
  include CompletionFields

  one :user, resource: UserSummaryResource
  one :game, resource: GameSummaryResource
  one :platform, resource: PlatformResource
end
