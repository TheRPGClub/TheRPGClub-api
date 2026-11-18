# frozen_string_literal: true

# A "See also" link between two Club Codex entries (spec #397, ticket #409).
# The pair is unordered: it is stored lower id first, one row per pair, and
# shows on both entries. It goes with either entry. Kept by
# ClubCodex::Links.
class CodexEntryLink < ApplicationRecord
  self.primary_key = %i[low_entry_id high_entry_id]

  # The stored row for a link between entries `a` and `b`, by id.
  def self.pair(a, b) = { low_entry_id: [ a, b ].min, high_entry_id: [ a, b ].max }

  # The links touching any of the entries `ids`.
  def self.touching(ids) = where(low_entry_id: ids).or(where(high_entry_id: ids))
end
