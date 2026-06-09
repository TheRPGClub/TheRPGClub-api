# frozen_string_literal: true

class GamedbSearchSynonymGroup < ApplicationRecord
  self.table_name = "gamedb_search_synonym_groups"
  self.primary_key = "group_id"

  has_many :synonyms,
    class_name: "GamedbSearchSynonym",
    foreign_key: :group_id,
    dependent: nil,
    inverse_of: :group
end
