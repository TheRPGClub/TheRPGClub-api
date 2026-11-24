# frozen_string_literal: true

# A list notice (spec api#442, ticket api#448): a Core Game of a Pool
# Challenge whose entry left the Challenge's linked Game List. It stays open
# until whoever may edit the Challenge removes the game from it or keeps it
# (Challenges::ListLink.resolve_notice!). Ending the link, or the game
# leaving the Core Games, clears it.
class ChallengePoolListNotice < ApplicationRecord
  belongs_to :challenge, inverse_of: :pool_list_notices
  belongs_to :game, class_name: "GamedbGame", foreign_key: :game_id, inverse_of: false
end
