# frozen_string_literal: true

class CreateUserGameBacklog < ActiveRecord::Migration[8.1]
  def up
    return if table_exists?(:user_game_backlog)

    create_table :user_game_backlog, primary_key: :entry_id do |table|
      table.string :user_id, limit: 50, null: false
      table.bigint :gamedb_game_id, null: false
      table.bigint :platform_id
      table.bigint :sort_order
      table.string :note, limit: 500
      table.datetime :created_at, precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
      table.datetime :updated_at, precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
    end

    add_index :user_game_backlog, %i[user_id gamedb_game_id platform_id],
              unique: true,
              name: "uq_user_game_backlog_user_game_platform"
    add_index :user_game_backlog, :user_id,
              name: "ix_user_game_backlog_user"
    add_index :user_game_backlog, %i[user_id sort_order],
              name: "ix_user_game_backlog_sort"
    add_index :user_game_backlog, :platform_id,
              name: "ix_user_game_backlog_platform"

    add_foreign_key :user_game_backlog,
                    :gamedb_games,
                    column: :gamedb_game_id,
                    primary_key: :game_id,
                    name: "fk_user_game_backlog_gamedb"
    add_foreign_key :user_game_backlog,
                    :gamedb_platforms,
                    column: :platform_id,
                    primary_key: :platform_id,
                    name: "fk_user_game_backlog_platform"
    add_foreign_key :user_game_backlog,
                    :rpg_club_users,
                    column: :user_id,
                    primary_key: :user_id,
                    name: "fk_user_game_backlog_user"
  end

  def down
    drop_table :user_game_backlog, if_exists: true
  end
end
