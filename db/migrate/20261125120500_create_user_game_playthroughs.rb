# frozen_string_literal: true

# Playthroughs (spec api#457, ticket api#459; GLOSSARY.md "Playthrough"): one
# run of a game by a member. Its time is `manual_total_minutes` when the member
# set one, else the member's Playtime minus `baseline_minutes` (the Playtime
# when it started), floored at 0.
#
# Open while `ended_at` is null; at most one open per member and game. It ends
# `completed` (a Game Completion closed it, `completion_id`) or `abandoned`,
# and `final_minutes` keeps its time at that moment.
class CreateUserGamePlaythroughs < ActiveRecord::Migration[8.1]
  def change
    create_table :user_game_playthroughs do |t|
      t.string :user_id, limit: 30, null: false
      t.bigint :gamedb_game_id, null: false
      t.datetime :started_at, null: false
      t.integer :baseline_minutes, null: false, default: 0
      t.integer :manual_total_minutes
      t.datetime :ended_at
      t.string :end_reason, limit: 16
      t.bigint :completion_id
      t.integer :final_minutes
      t.timestamps
    end

    add_index :user_game_playthroughs, %i[user_id gamedb_game_id], unique: true, where: "ended_at IS NULL",
      name: "ux_user_game_playthroughs_open"
    add_index :user_game_playthroughs, :gamedb_game_id
    add_index :user_game_playthroughs, :completion_id
    add_check_constraint :user_game_playthroughs, "end_reason IN ('completed', 'abandoned')",
      name: "ck_user_game_playthroughs_end_reason"
    add_check_constraint :user_game_playthroughs, "(ended_at IS NULL) = (end_reason IS NULL)",
      name: "ck_user_game_playthroughs_ended"
    add_check_constraint :user_game_playthroughs,
      "baseline_minutes >= 0 AND manual_total_minutes >= 0 AND final_minutes >= 0",
      name: "ck_user_game_playthroughs_minutes"
    add_foreign_key :user_game_playthroughs, :rpg_club_users, column: :user_id, primary_key: :user_id,
      on_delete: :cascade
    add_foreign_key :user_game_playthroughs, :gamedb_games, column: :gamedb_game_id, primary_key: :game_id,
      on_delete: :cascade
    add_foreign_key :user_game_playthroughs, :user_game_completions, column: :completion_id,
      primary_key: :completion_id, on_delete: :nullify
  end
end
