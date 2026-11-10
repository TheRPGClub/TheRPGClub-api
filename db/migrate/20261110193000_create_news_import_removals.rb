# frozen_string_literal: true

# News Import removals (GLOSSARY.md, "News Hub"; spec #355, ticket #359):
# one row per Game News Archive message staff removed with `skip`. The News
# Item itself is deleted; this row remembers the removal so a later re-scan
# does not bring the message back. `removed_by` is the acting staff member's
# Discord id, kept without a foreign key like other "changed by" columns.
class CreateNewsImportRemovals < ActiveRecord::Migration[8.1]
  def change
    create_table :news_import_removals do |t|
      t.string :message_id, limit: 30, null: false
      t.string :removed_by, limit: 30
      t.datetime :created_at, null: false
    end

    add_index :news_import_removals, :message_id, unique: true
  end
end
