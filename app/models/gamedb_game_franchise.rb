# frozen_string_literal: true

# A game's membership of a Franchise (GLOSSARY.md, "Franchise"). `source` says
# where the link came from: `igdb` (an import) or `manual` (a Regular or above
# added it). `mainline` marks the game as one of the Franchise's main entries
# (GLOSSARY.md, "Mainline"). Hand changes go through Gamedb::FranchiseEditor.
class GamedbGameFranchise < ApplicationRecord
  self.table_name = "gamedb_game_franchises"
  self.primary_key = %i[game_id franchise_id]

  SOURCES = %w[igdb manual].freeze

  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :game_id,
    inverse_of: :game_franchises
  belongs_to :franchise,
    class_name: "GamedbFranchise",
    foreign_key: :franchise_id,
    inverse_of: :game_franchises

  validates :source, inclusion: { in: SOURCES }
end
