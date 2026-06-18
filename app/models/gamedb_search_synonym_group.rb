# frozen_string_literal: true

class GamedbSearchSynonymGroup < ApplicationRecord
  self.table_name = "gamedb_search_synonym_groups"
  self.primary_key = "group_id"

  # `dependent: :destroy` mirrors the DB-level `ON DELETE CASCADE` on
  # `gamedb_search_synonyms.group_id` (#108): deleting a group removes its terms.
  has_many :synonyms,
    class_name: "GamedbSearchSynonym",
    foreign_key: :group_id,
    dependent: :destroy,
    inverse_of: :group
end
