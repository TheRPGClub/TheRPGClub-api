# frozen_string_literal: true

# A Franchise (GLOSSARY.md): a broad grouping of GameDB games under one brand.
# Most come from IGDB (`igdb_franchise_id`); one a Regular or above created
# has no IGDB id and records `created_by`.
class GamedbFranchise < ApplicationRecord
  self.table_name = "gamedb_franchises"
  self.primary_key = "franchise_id"

  has_many :game_franchises,
    class_name: "GamedbGameFranchise",
    foreign_key: :franchise_id,
    dependent: nil,
    inverse_of: :franchise
  has_many :games,
    through: :game_franchises,
    source: :game

  validates :name, presence: true, length: { maximum: 255 }
end
