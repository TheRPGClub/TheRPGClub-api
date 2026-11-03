# frozen_string_literal: true

# Serializes a GamedbSearchSynonymGroup (all columns), plus its terms under
# `terms` (sorted by text) when the controller passes `include_terms: true`
# (`?include=terms`, web parity 2 #333). The key is omitted otherwise.
class SearchSynonymGroupResource
  include BaseResource

  columns_of GamedbSearchSynonymGroup
  many :synonyms,
    proc { |synonyms| synonyms.sort_by { |s| [ s.term_text, s.term_id ] } },
    key: :terms,
    resource: SearchSynonymResource,
    if: proc { params[:include_terms] }
end
