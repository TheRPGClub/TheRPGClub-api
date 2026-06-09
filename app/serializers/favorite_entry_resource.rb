# frozen_string_literal: true

# A UserGameFavorite with its embedded game. Replaces the legacy
# `serialize_with_game` helper: all favorite columns plus `game`. Favorites have
# no platform association.
class FavoriteEntryResource
  include BaseResource

  columns_of UserGameFavorite
  one :game, resource: GameSummaryResource
end
