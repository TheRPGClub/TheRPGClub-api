# frozen_string_literal: true

class GamedbSearchSynonym < ApplicationRecord
  self.table_name = "gamedb_search_synonyms"
  self.primary_key = "term_id"

  belongs_to :group,
    class_name: "GamedbSearchSynonymGroup",
    foreign_key: :group_id,
    inverse_of: :synonyms

  validates :term_text, :term_norm, presence: true
end
