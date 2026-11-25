# frozen_string_literal: true

# Game of the Year nominations (spec api#471, ticket api#473): a member
# nominates up to three games for a year's Game of the Year, each once. The
# cap of three is enforced in Goty::Nominate under an advisory lock.
class CreateGotyNominations < ActiveRecord::Migration[8.1]
  def change
    create_table :goty_nominations do |t|
      t.integer :year, null: false
      t.string :user_id, limit: 64, null: false
      t.bigint :gamedb_game_id, null: false
      t.string :reason, limit: 1500
      t.datetime :nominated_at, precision: 6, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.timestamps
    end

    add_index :goty_nominations, %i[year user_id gamedb_game_id], unique: true,
      name: "ux_goty_nominations_year_user_game"
    add_index :goty_nominations, %i[year gamedb_game_id], name: "ix_goty_nominations_year_game"
    add_foreign_key :goty_nominations, :goty_votes, column: :year, primary_key: :year, on_delete: :cascade
    add_foreign_key :goty_nominations, :rpg_club_users, column: :user_id, primary_key: :user_id, on_delete: :cascade
    add_foreign_key :goty_nominations, :gamedb_games, column: :gamedb_game_id, primary_key: :game_id,
      on_delete: :cascade
  end
end
