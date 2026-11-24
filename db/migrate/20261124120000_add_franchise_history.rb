# frozen_string_literal: true

# Franchise history, rename, merge and delete (spec api#442, ticket api#444).
#
# - `gamedb_franchise_changes` records every hand change to a Franchise
#   (Gamedb::FranchiseEditor). It has no foreign key to the Franchise, so the
#   rows of a deleted Franchise stay as an audit trail.
# - `gamedb_franchises.name_locked` marks a name a person set, so a re-import
#   keeps it; `merged_into_id` points a merged Franchise at the one it went
#   into, so re-imports naming its IGDB id resolve there.
# - `gamedb_deleted_franchises` remembers the IGDB id of a deleted Franchise,
#   so a re-import doesn't create it again.
class AddFranchiseHistory < ActiveRecord::Migration[8.1]
  ACTIONS = %w[link unlink mainline_on mainline_off create rename merge delete].freeze

  def change
    create_table :gamedb_franchise_changes do |t|
      t.bigint :franchise_id, null: false
      t.bigint :game_id
      t.string :action, limit: 20, null: false
      t.jsonb :before
      t.jsonb :after
      t.string :user_id, limit: 30
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :undone_at
      t.string :undone_by, limit: 30
      t.index %i[franchise_id id], name: "ix_gamedb_franchise_changes_franchise"
      t.index %i[franchise_id game_id id], name: "ix_gamedb_franchise_changes_game"
      t.check_constraint "action IN (#{ACTIONS.map { |a| "'#{a}'" }.join(', ')})",
        name: "ck_gamedb_franchise_changes_action"
    end
    add_foreign_key :gamedb_franchise_changes, :gamedb_games, column: :game_id, primary_key: :game_id,
      on_delete: :cascade

    change_table :gamedb_franchises, bulk: true do |t|
      t.boolean :name_locked, null: false, default: false
      t.bigint :merged_into_id
    end
    add_foreign_key :gamedb_franchises, :gamedb_franchises, column: :merged_into_id, primary_key: :franchise_id
    add_index :gamedb_franchises, :merged_into_id

    create_table :gamedb_deleted_franchises, primary_key: :igdb_franchise_id do |t|
      t.string :name, limit: 255, null: false
      t.string :deleted_by, limit: 30
      t.datetime :deleted_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
  end
end
