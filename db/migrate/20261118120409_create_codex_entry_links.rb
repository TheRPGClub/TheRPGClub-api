# frozen_string_literal: true

# "See also" links between Club Codex entries (spec #397, ticket #409).
#
# A link is an unordered pair of entries, so one row shows on both. The pair
# is stored with the lower id first, which makes it unique per pair (one
# row, whichever side set it) and rules out a self-link. A link goes when
# either of its entries does.
class CreateCodexEntryLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :codex_entry_links, primary_key: %i[low_entry_id high_entry_id] do |t|
      t.bigint :low_entry_id, null: false
      t.bigint :high_entry_id, null: false
      t.timestamptz :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }

      t.check_constraint "low_entry_id < high_entry_id", name: "ck_codex_entry_links_ordered_pair"
    end
    add_index :codex_entry_links, :high_entry_id, name: "ix_codex_entry_links_high"
    add_foreign_key :codex_entry_links, :codex_entries, column: :low_entry_id, on_delete: :cascade,
      name: "fk_codex_entry_links_low"
    add_foreign_key :codex_entry_links, :codex_entries, column: :high_entry_id, on_delete: :cascade,
      name: "fk_codex_entry_links_high"
  end
end
