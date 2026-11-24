# frozen_string_literal: true

# A UserGameBacklog with its embedded game and platform. `platform` renders
# `null` when the entry has no platform.
#
# Consumer-audited allowlist (#36): the entry PK (`entry_id`), `user_id`,
# `gamedb_game_id`, `platform_id`, `note` and `sort_order` (the website's
# reorder, spec api#451) are read; `created_at` and `updated_at` are dropped.
class BacklogEntryResource
  include BaseResource

  attributes :entry_id, :user_id, :gamedb_game_id, :platform_id, :note, :sort_order
  one :game, resource: GameSummaryResource
  one :platform, resource: PlatformResource
end
