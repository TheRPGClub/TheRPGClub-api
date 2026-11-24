# frozen_string_literal: true

# A game a person removed from a Franchise. An IGDB re-import never links the
# pair again; linking it again by hand deletes this row
# (Gamedb::FranchiseEditor).
class GamedbFranchiseUnlink < ApplicationRecord
  self.table_name = "gamedb_franchise_unlinks"
  self.primary_key = %i[game_id franchise_id]

  belongs_to :game, class_name: "GamedbGame", foreign_key: :game_id, inverse_of: false
  belongs_to :franchise, class_name: "GamedbFranchise", foreign_key: :franchise_id, inverse_of: false
end
