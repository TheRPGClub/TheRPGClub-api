# frozen_string_literal: true

# The IGDB id of a Franchise an Admin deleted, so an IGDB re-import doesn't
# create it again (spec api#442; GamedbFranchise.for_igdb_ref).
class GamedbDeletedFranchise < ApplicationRecord
  self.table_name = "gamedb_deleted_franchises"
  self.primary_key = "igdb_franchise_id"
end
