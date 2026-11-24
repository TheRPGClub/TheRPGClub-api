# frozen_string_literal: true

# A game in a Game List (spec api#442, ticket api#446): the game, its place
# in the ranked order, its note and when it was added.
class GameListEntryResource
  include BaseResource

  attributes :game_id, :position, :note, :added_at

  attribute :game do |entry|
    GameSummaryResource.new(entry.game).serializable_hash
  end
end
