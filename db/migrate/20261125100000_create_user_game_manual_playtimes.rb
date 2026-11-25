# frozen_string_literal: true

# Manual Playtime (spec api#457, ticket api#458; GLOSSARY.md "Manual
# Playtime", ADR 0015): time a member records for a game themselves, against
# one platform. A null platform is "Other". One entry per member, game and
# platform, with "Other" counting as one platform (nulls not distinct).
#
# `keeps_over_provider` is the Provider this entry replaces on its platform
# after the member chose "keep mine" in a mismatch; that Provider's figure for
# the platform is then shown but not counted (Playtime::Ledger).
class CreateUserGameManualPlaytimes < ActiveRecord::Migration[8.1]
  def change
    create_table :user_game_manual_playtimes do |t|
      t.string :user_id, limit: 30, null: false
      t.bigint :gamedb_game_id, null: false
      t.bigint :platform_id
      t.integer :minutes, null: false, default: 0
      t.string :note, limit: 280
      t.string :origin, limit: 32, null: false, default: "member"
      t.string :keeps_over_provider, limit: 32
      t.timestamps
    end

    add_index :user_game_manual_playtimes, %i[user_id gamedb_game_id platform_id], unique: true,
      nulls_not_distinct: true, name: "ux_user_game_manual_playtimes_platform"
    add_index :user_game_manual_playtimes, :gamedb_game_id
    add_check_constraint :user_game_manual_playtimes, "minutes >= 0", name: "ck_user_game_manual_playtimes_minutes"
    add_check_constraint :user_game_manual_playtimes, "origin IN ('member', 'completion_seed')",
      name: "ck_user_game_manual_playtimes_origin"
    add_foreign_key :user_game_manual_playtimes, :rpg_club_users, column: :user_id, primary_key: :user_id,
      on_delete: :cascade
    add_foreign_key :user_game_manual_playtimes, :gamedb_games, column: :gamedb_game_id, primary_key: :game_id,
      on_delete: :cascade
    add_foreign_key :user_game_manual_playtimes, :gamedb_platforms, column: :platform_id, primary_key: :platform_id
  end
end
