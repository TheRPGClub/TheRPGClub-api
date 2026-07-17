# frozen_string_literal: true

class CreateRpgClubCollectionCsvImports < ActiveRecord::Migration[8.1]
  def up
    create_imports_table unless table_exists?(:rpg_club_collection_csv_imports)
    create_items_table unless table_exists?(:rpg_club_collection_csv_import_items)
  end

  def down
    drop_table :rpg_club_collection_csv_import_items, if_exists: true
    drop_table :rpg_club_collection_csv_imports, if_exists: true
  end

  private

  def create_imports_table
    create_table :rpg_club_collection_csv_imports, primary_key: :import_id do |table|
      table.string :user_id, limit: 30, null: false
      table.string :status, limit: 20, null: false
      table.bigint :current_index, default: 0, null: false
      table.bigint :total_count, default: 0, null: false
      table.string :source_file_name, limit: 255
      table.bigint :source_file_size
      table.string :template_version, limit: 20
      table.column :created_at, "timestamp(6) with time zone", default: -> { "statement_timestamp()" }, null: false
      table.column :updated_at, "timestamp(6) with time zone", default: -> { "statement_timestamp()" }, null: false
    end

    add_check_constraint :rpg_club_collection_csv_imports,
                         "status IN ('ACTIVE', 'PAUSED', 'COMPLETED', 'CANCELED')",
                         name: "ck_coll_csv_imports_status"
    add_index :rpg_club_collection_csv_imports, %i[user_id status], name: "ix_coll_csv_imports_user"
  end

  def create_items_table
    create_table :rpg_club_collection_csv_import_items, primary_key: :item_id do |table|
      table.bigint :import_id, null: false
      table.bigint :row_index, null: false
      table.string :raw_title, limit: 500
      table.string :raw_platform, limit: 200
      table.string :raw_ownership_type, limit: 60
      table.string :raw_note, limit: 500
      table.bigint :raw_gamedb_id
      table.bigint :raw_igdb_id
      table.bigint :platform_id
      table.string :ownership_type, limit: 30
      table.string :note, limit: 500
      table.string :status, limit: 20, null: false
      table.string :match_confidence, limit: 20
      table.text :match_candidate_json
      table.bigint :gamedb_game_id
      table.bigint :collection_entry_id
      table.string :result_reason, limit: 40
      table.string :error_text, limit: 2000
    end

    add_foreign_key :rpg_club_collection_csv_import_items,
                    :rpg_club_collection_csv_imports,
                    column: :import_id,
                    primary_key: :import_id,
                    name: "fk_coll_csv_import_items"
    add_check_constraint :rpg_club_collection_csv_import_items,
                         "status IN ('PENDING', 'ADDED', 'UPDATED', 'SKIPPED', 'FAILED')",
                         name: "ck_coll_csv_items_status"
    add_index :rpg_club_collection_csv_import_items,
              %i[import_id status row_index],
              name: "ix_coll_csv_items_import"
    add_index :rpg_club_collection_csv_import_items, %i[import_id row_index],
              unique: true,
              name: "ux_coll_csv_items_import_row"
  end
end
