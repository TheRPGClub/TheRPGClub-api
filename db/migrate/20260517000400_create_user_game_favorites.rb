# frozen_string_literal: true

class CreateUserGameFavorites < ActiveRecord::Migration[8.1]
  def up
    return if table_exists?(:user_game_favorites)

    create_table :user_game_favorites, primary_key: :entry_id do |table|
      table.string :user_id, limit: 50, null: false
      table.bigint :gamedb_game_id, null: false
      table.bigint :sort_order
      table.string :note, limit: 500
      table.datetime :created_at, precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
      table.datetime :updated_at, precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
    end

    add_index :user_game_favorites, %i[user_id gamedb_game_id],
              unique: true,
              name: "uq_user_game_favorites_user_game"
    add_index :user_game_favorites, %i[user_id sort_order],
              name: "ix_user_game_favorites_sort"
    add_index :user_game_favorites, :gamedb_game_id,
              name: "ix_user_game_favorites_game"

    add_foreign_key :user_game_favorites,
                    :gamedb_games,
                    column: :gamedb_game_id,
                    primary_key: :game_id,
                    name: "fk_user_game_favorites_gamedb"
    add_foreign_key :user_game_favorites,
                    :rpg_club_users,
                    column: :user_id,
                    primary_key: :user_id,
                    name: "fk_user_game_favorites_user"
  end

  def down
    drop_table :user_game_favorites, if_exists: true
  end
end
