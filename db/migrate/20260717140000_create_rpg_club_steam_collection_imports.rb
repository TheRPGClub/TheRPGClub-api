# frozen_string_literal: true

# rpg_club_steam_collection_imports / _items already exist (bot-scaffolded,
# uppercase Oracle-era enum values, no test_mode column). This migration
# brings them into the API's conventions in place, preserving any existing
# rows, rather than dropping and recreating.
class CreateRpgClubSteamCollectionImports < ActiveRecord::Migration[8.1]
  def up
    if table_exists?(:rpg_club_steam_collection_imports)
      migrate_imports_table
    else
      create_imports_table
    end

    if table_exists?(:rpg_club_steam_collection_import_items)
      migrate_items_table
    else
      create_items_table
    end
  end

  def down
    drop_table :rpg_club_steam_collection_import_items, if_exists: true
    drop_table :rpg_club_steam_collection_imports, if_exists: true
  end

  private

  def create_imports_table
    create_table :rpg_club_steam_collection_imports, primary_key: :import_id do |table|
      table.string :user_id, limit: 30, null: false
      table.string :status, limit: 20, null: false
      table.bigint :current_index, default: 0, null: false
      table.bigint :total_count, default: 0, null: false
      table.string :steam_id64, limit: 20, null: false
      table.string :steam_profile_ref, limit: 255
      table.string :source_profile_name, limit: 255
      table.boolean :test_mode, default: false, null: false
      table.column :created_at, "timestamp(6) with time zone", default: -> { "statement_timestamp()" }, null: false
      table.column :updated_at, "timestamp(6) with time zone", default: -> { "statement_timestamp()" }, null: false
    end

    add_check_constraint :rpg_club_steam_collection_imports,
                         "status IN ('active', 'paused', 'completed', 'canceled')",
                         name: "ck_steam_coll_imports_status"
    add_index :rpg_club_steam_collection_imports, %i[user_id status], name: "ix_steam_coll_imports_user"
  end

  def migrate_imports_table
    remove_check_constraint :rpg_club_steam_collection_imports, name: "ck_steam_coll_imports_status"
    execute "UPDATE rpg_club_steam_collection_imports SET status = lower(status)"
    add_check_constraint :rpg_club_steam_collection_imports,
                         "status IN ('active', 'paused', 'completed', 'canceled')",
                         name: "ck_steam_coll_imports_status"

    return if column_exists?(:rpg_club_steam_collection_imports, :test_mode)

    add_column :rpg_club_steam_collection_imports, :test_mode, :boolean, default: false, null: false
  end

  def create_items_table
    create_table :rpg_club_steam_collection_import_items, primary_key: :item_id do |table|
      table.bigint :import_id, null: false
      table.bigint :row_index, null: false
      table.bigint :steam_app_id, null: false
      table.string :steam_app_name, limit: 500, null: false
      table.bigint :playtime_forever_min
      table.bigint :playtime_windows_min
      table.bigint :playtime_mac_min
      table.bigint :playtime_linux_min
      table.bigint :playtime_deck_min
      table.column :last_played_at, "timestamp(0) without time zone"
      table.string :status, limit: 20, null: false
      table.string :match_confidence, limit: 20
      table.text :match_candidate_json
      table.bigint :gamedb_game_id
      table.bigint :collection_entry_id
      table.string :error_text, limit: 2000
      table.string :result_reason, limit: 40
    end

    add_foreign_key :rpg_club_steam_collection_import_items,
                    :rpg_club_steam_collection_imports,
                    column: :import_id,
                    primary_key: :import_id,
                    name: "fk_steam_coll_import_items"
    add_check_constraint :rpg_club_steam_collection_import_items,
                         "status IN ('pending', 'added', 'updated', 'skipped', 'failed')",
                         name: "ck_steam_coll_items_status"
    add_check_constraint :rpg_club_steam_collection_import_items, match_confidence_check_sql,
                         name: "ck_steam_coll_items_match_confidence"
    add_check_constraint :rpg_club_steam_collection_import_items, result_reason_check_sql,
                         name: "ck_steam_coll_items_reason"
    add_index :rpg_club_steam_collection_import_items,
              %i[import_id status row_index],
              name: "ix_steam_coll_items_import"
    add_index :rpg_club_steam_collection_import_items, %i[import_id row_index],
              unique: true,
              name: "ux_steam_coll_items_import_row"
  end

  def migrate_items_table
    remove_check_constraint :rpg_club_steam_collection_import_items, name: "ck_steam_coll_items_status"
    remove_check_constraint :rpg_club_steam_collection_import_items, name: "ck_steam_coll_items_reason"

    execute "UPDATE rpg_club_steam_collection_import_items SET status = lower(status)"
    execute "UPDATE rpg_club_steam_collection_import_items SET result_reason = lower(result_reason) " \
            "WHERE result_reason IS NOT NULL"
    execute "UPDATE rpg_club_steam_collection_import_items SET match_confidence = lower(match_confidence) " \
            "WHERE match_confidence IS NOT NULL"

    add_check_constraint :rpg_club_steam_collection_import_items,
                         "status IN ('pending', 'added', 'updated', 'skipped', 'failed')",
                         name: "ck_steam_coll_items_status"
    add_check_constraint :rpg_club_steam_collection_import_items, result_reason_check_sql,
                         name: "ck_steam_coll_items_reason"
    add_check_constraint :rpg_club_steam_collection_import_items, match_confidence_check_sql,
                         name: "ck_steam_coll_items_match_confidence"

    unless index_exists?(:rpg_club_steam_collection_import_items, %i[import_id row_index],
      name: "ux_steam_coll_items_import_row")
      add_index :rpg_club_steam_collection_import_items, %i[import_id row_index],
                unique: true,
                name: "ux_steam_coll_items_import_row"
    end
  end

  def match_confidence_check_sql
    "match_confidence IS NULL OR match_confidence IN ('exact', 'fuzzy', 'manual')"
  end

  def result_reason_check_sql
    reasons = %w[auto_match manual_remap duplicate manual_skip skip_mapped
                 no_candidate invalid_remap platform_unresolved add_failed]
    "result_reason IS NULL OR result_reason IN (#{reasons.map { |r| "'#{r}'" }.join(', ')})"
  end
end
