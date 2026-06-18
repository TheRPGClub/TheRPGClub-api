# frozen_string_literal: true

class GamedbSearchSynonym < ApplicationRecord
  self.table_name = "gamedb_search_synonyms"
  self.primary_key = "term_id"

  belongs_to :group,
    class_name: "GamedbSearchSynonymGroup",
    foreign_key: :group_id,
    inverse_of: :synonyms

  validates :term_text, :term_norm, presence: true

  # Mirror the bot's `normalizeSearchTerm` (and PresencePromptOpt.normalize_title):
  # lowercase, then strip every non-alphanumeric character. Used to normalise the
  # `?term=`/`?q=` lookup inputs before matching against the stored `term_norm`.
  def self.normalize_term(text)
    text.to_s.downcase.gsub(/[^a-z0-9]/, "")
  end
end
