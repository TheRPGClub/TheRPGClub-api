# frozen_string_literal: true

# A Franchise (GLOSSARY.md): a broad grouping of GameDB games under one brand.
# Most come from IGDB (`igdb_franchise_id`); one a Regular or above created
# has no IGDB id and records `created_by`.
#
# An Admin can rename one (`name_locked`, so a re-import keeps the name),
# merge it into another (`merged_into_id`) or delete it (spec api#442). A
# merged Franchise keeps its row so re-imports naming its IGDB id resolve to
# the target, but it leaves the list and search (`current`).
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

  belongs_to :merged_into, class_name: "GamedbFranchise", optional: true, inverse_of: false

  scope :current, -> { where(merged_into_id: nil) }

  validates :name, presence: true, length: { maximum: 255 }

  # The Franchise an IGDB franchise reference (`{ igdb_id:, name: }`) lands
  # in on import: created if it is new, the target if it was merged, and nil
  # if an Admin deleted it.
  def self.for_igdb_ref(ref)
    return nil if GamedbDeletedFranchise.exists?(igdb_franchise_id: ref[:igdb_id])

    franchise = create_with(name: ref[:name]).find_or_create_by!(igdb_franchise_id: ref[:igdb_id])
    franchise.merged_into || franchise
  end

  def merged? = merged_into_id.present?
end
