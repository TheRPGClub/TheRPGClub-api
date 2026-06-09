# frozen_string_literal: true

class GamedbSearchSynonymDraft < ApplicationRecord
  self.table_name = "gamedb_search_synonym_drafts"
  self.primary_key = "draft_id"

  validates :user_id, presence: true
end
