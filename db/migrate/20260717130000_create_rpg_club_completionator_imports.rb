# frozen_string_literal: true

class CreateRpgClubCompletionatorImports < ActiveRecord::Migration[8.1]
  def up
    create_imports_table unless table_exists?(:rpg_club_completionator_imports)
    create_items_table unless table_exists?(:rpg_club_completionator_import_items)
  end

  def down
    drop_table :rpg_club_completionator_import_items, if_exists: true
    drop_table :rpg_club_completionator_imports, if_exists: true
  end

  private

  def create_imports_table
    create_table :rpg_club_completionator_imports, primary_key: :import_id do |table|
      table.string :user_id, limit: 30, null: false
      table.string :status, limit: 20, null: false
      table.bigint :current_index, default: 0, null: false
      table.bigint :total_count, default: 0, null: false
      table.string :source_filename, limit: 255
      table.column :created_at, "timestamp(6) with time zone", default: -> { "statement_timestamp()" }, null: false
      table.column :updated_at, "timestamp(6) with time zone", default: -> { "statement_timestamp()" }, null: false
    end

    add_check_constraint :rpg_club_completionator_imports,
                         "status IN ('active', 'paused', 'completed', 'canceled')",
                         name: "ck_completionator_imports_status"
    add_index :rpg_club_completionator_imports, %i[user_id status], name: "ix_completionator_imports_user"
  end

  def create_items_table
    create_table :rpg_club_completionator_import_items, primary_key: :item_id do |table|
      table.bigint :import_id, null: false
      table.bigint :row_index, null: false
      table.string :game_title, limit: 500
      table.string :platform_name, limit: 200
      table.string :region_name, limit: 100
      table.string :source_type, limit: 60
      table.string :time_text, limit: 100
      table.timestamp :completed_at
      table.string :completion_type, limit: 50
      table.decimal :playtime_hrs, precision: 8, scale: 2
      table.string :status, limit: 20, null: false
      table.bigint :gamedb_game_id
      table.bigint :completion_id
      table.string :error_text, limit: 2000
    end

    add_foreign_key :rpg_club_completionator_import_items,
                    :rpg_club_completionator_imports,
                    column: :import_id,
                    primary_key: :import_id,
                    name: "fk_completionator_import_items"
    add_check_constraint :rpg_club_completionator_import_items,
                         "status IN ('pending', 'added', 'updated', 'skipped', 'failed')",
                         name: "ck_completionator_items_status"
    add_index :rpg_club_completionator_import_items,
              %i[import_id status row_index],
              name: "ix_completionator_items_import"
    add_index :rpg_club_completionator_import_items, %i[import_id row_index],
              unique: true,
              name: "ux_completionator_items_import_row"
  end
end
