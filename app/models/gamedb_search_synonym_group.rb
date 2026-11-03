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

  # A replace-terms request the bot's rules refuse (#333).
  class InvalidTerms < StandardError; end

  # Swap all of the group's terms for `texts` in one transaction (#333), so an
  # edit can never leave the group half saved. Mirrors the bot's
  # updateGroupTerms: terms are trimmed, blanks dropped, a term normalising like
  # an earlier one is skipped, every term needs a letter or number, and the
  # group keeps at least two terms.
  #
  # @raise [InvalidTerms] when the terms break those rules (nothing is changed)
  def replace_terms!(texts, created_by:)
    terms = clean_terms(texts)
    transaction do
      synonyms.delete_all
      terms.each do |text, norm|
        synonyms.create!(term_text: text, term_norm: norm, created_by: created_by)
      end
    end
    synonyms.reset
    self
  end

  private

  def clean_terms(texts)
    raise InvalidTerms, "terms must be a list of strings." unless texts.is_a?(Array) && texts.all?(String)

    terms = {}
    texts.map(&:strip).reject(&:empty?).each do |text|
      norm = GamedbSearchSynonym.normalize_term(text)
      raise InvalidTerms, "Synonym terms must include letters or numbers." if norm.empty?

      terms[norm] ||= text
    end
    raise InvalidTerms, "A synonym group needs at least two different terms." if terms.size < 2

    terms.map { |norm, text| [ text, norm ] }
  end
end
