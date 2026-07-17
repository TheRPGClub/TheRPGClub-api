# frozen_string_literal: true

# rpg_club_steam_app_gamedb_map already exists (bot-scaffolded, uppercase
# Oracle-era enum values). This migration lowercases the existing status
# values in place and adds the missing (created_by, status) index, rather
# than dropping and recreating.
class CreateRpgClubSteamAppGamedbMap < ActiveRecord::Migration[8.1]
  def up
    if table_exists?(:rpg_club_steam_app_gamedb_map)
      migrate_table
    else
      create_table_fresh
    end
  end

  def down
    drop_table :rpg_club_steam_app_gamedb_map, if_exists: true
  end

  private

  def create_table_fresh
    create_table :rpg_club_steam_app_gamedb_map, primary_key: :map_id do |table|
      table.bigint :steam_app_id, null: false
      table.bigint :gamedb_game_id
      table.string :status, limit: 20, null: false
      table.string :created_by, limit: 30
      table.column :created_at, "timestamp(6) with time zone", default: -> { "statement_timestamp()" }, null: false
      table.column :updated_at, "timestamp(6) with time zone", default: -> { "statement_timestamp()" }, null: false
    end

    add_check_constraint :rpg_club_steam_app_gamedb_map,
                         "status IN ('mapped', 'skipped')",
                         name: "ck_steam_app_gamedb_map_status"
    add_index :rpg_club_steam_app_gamedb_map, :steam_app_id, unique: true, name: "ux_steam_app_gamedb_map_app"
    add_index :rpg_club_steam_app_gamedb_map, %i[created_by status], name: "ix_steam_app_gamedb_map_creator"
  end

  def migrate_table
    remove_check_constraint :rpg_club_steam_app_gamedb_map, name: "ck_steam_app_gamedb_map_status"
    execute "UPDATE rpg_club_steam_app_gamedb_map SET status = lower(status)"
    add_check_constraint :rpg_club_steam_app_gamedb_map,
                         "status IN ('mapped', 'skipped')",
                         name: "ck_steam_app_gamedb_map_status"

    return if index_exists?(:rpg_club_steam_app_gamedb_map, %i[created_by status], name: "ix_steam_app_gamedb_map_creator")

    add_index :rpg_club_steam_app_gamedb_map, %i[created_by status], name: "ix_steam_app_gamedb_map_creator"
  end
end
