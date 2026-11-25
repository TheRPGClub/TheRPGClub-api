# frozen_string_literal: true

# A UserGameFavorite with its embedded game. Favorites have no platform
# association.
#
# Consumer-audited allowlist (#36): the entry PK (`entry_id`), `user_id`
# (game-scoped lists dedup players by it), `gamedb_game_id` and `note` are
# read, as is `sort_order` (the website's reorder, spec api#451); `created_at`
# and `updated_at` are dropped from output.
class FavoriteEntryResource
  include BaseResource
  include ShelfPlaytimeFields.with

  attributes :entry_id, :user_id, :gamedb_game_id, :note, :sort_order
  one :game, resource: GameSummaryResource
end
