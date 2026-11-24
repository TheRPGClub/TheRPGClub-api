# frozen_string_literal: true

# Franchise editing (spec api#442, ticket api#443): Regulars and above link
# and unlink games, mark Mainline and create Franchises, and those edits
# survive IGDB re-imports.
#
# - A link records where it came from (`igdb` or `manual`), whether the game
#   is Mainline in that Franchise, and who added it when. Existing links all
#   came from IGDB, are not Mainline, and have no known `created_at`; links
#   added from now on get one.
# - `gamedb_franchise_unlinks` remembers a link a person removed, so a
#   re-import never adds it back. Linking the pair again by hand deletes it.
# - A Franchise records who created it (null for IGDB's).
class AddFranchiseEditing < ActiveRecord::Migration[8.1]
  def up
    change_table :gamedb_game_franchises, bulk: true do |t|
      t.string :source, limit: 10, null: false, default: "igdb"
      t.boolean :mainline, null: false, default: false
      t.datetime :created_at
      t.string :created_by, limit: 30
    end
    change_column_default :gamedb_game_franchises, :created_at, from: nil, to: -> { "CURRENT_TIMESTAMP" }
    add_check_constraint :gamedb_game_franchises, "source IN ('igdb', 'manual')", name: "ck_gamedb_game_franchises_source"
    add_index :gamedb_game_franchises, :franchise_id

    create_table :gamedb_franchise_unlinks, primary_key: %i[game_id franchise_id] do |t|
      t.bigint :game_id, null: false
      t.bigint :franchise_id, null: false
      t.string :unlinked_by, limit: 30
      t.datetime :unlinked_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
    add_foreign_key :gamedb_franchise_unlinks, :gamedb_games, column: :game_id, primary_key: :game_id,
      on_delete: :cascade
    add_foreign_key :gamedb_franchise_unlinks, :gamedb_franchises, column: :franchise_id,
      primary_key: :franchise_id, on_delete: :cascade

    add_column :gamedb_franchises, :created_by, :string, limit: 30
  end

  def down
    remove_column :gamedb_franchises, :created_by
    drop_table :gamedb_franchise_unlinks
    remove_index :gamedb_game_franchises, :franchise_id
    remove_check_constraint :gamedb_game_franchises, name: "ck_gamedb_game_franchises_source"
    change_table :gamedb_game_franchises, bulk: true do |t|
      t.remove :source, :mainline, :created_at, :created_by
    end
  end
end
