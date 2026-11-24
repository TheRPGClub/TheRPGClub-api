# frozen_string_literal: true

# A game in a Game List (spec api#442, ticket api#446): at most once per
# list, with its place in the ranked order, an optional note and when it
# was added. Written through GameLists::Entries.
class GameListEntry < ApplicationRecord
  NOTE_MAX = 280

  self.primary_key = %i[game_list_id game_id]

  belongs_to :game_list, inverse_of: :entries, touch: true
  belongs_to :game, class_name: "GamedbGame", foreign_key: :game_id, inverse_of: false

  validates :note, length: { maximum: NOTE_MAX }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  normalizes :note, with: ->(value) { value.strip.presence }
end
