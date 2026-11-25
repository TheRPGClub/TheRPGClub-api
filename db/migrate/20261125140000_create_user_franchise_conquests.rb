# frozen_string_literal: true

# Conquests (spec api#457, ticket api#461; GLOSSARY.md "Conquered"): a member
# has Conquered a Franchise once they hold a Game Completion for every
# Mainline game in it. One row per member and Franchise, written once by
# Franchises::ConquestCheck and never removed by later Mainline additions or
# deleted Completions (the Completion FK nulls out instead).
#
# `announce` is false for Conquests that are not posted: the launch backfill
# and Completionator imports.
class CreateUserFranchiseConquests < ActiveRecord::Migration[8.1]
  def change
    create_table :user_franchise_conquests do |t|
      t.string :user_id, limit: 30, null: false
      t.bigint :franchise_id, null: false
      t.datetime :conquered_at, null: false
      t.bigint :completion_id
      t.boolean :announce, null: false, default: true
      t.timestamps
    end

    add_index :user_franchise_conquests, %i[user_id franchise_id], unique: true,
      name: "ux_user_franchise_conquests_member"
    add_index :user_franchise_conquests, :franchise_id
    add_foreign_key :user_franchise_conquests, :rpg_club_users, column: :user_id, primary_key: :user_id,
      on_delete: :cascade
    add_foreign_key :user_franchise_conquests, :gamedb_franchises, column: :franchise_id,
      primary_key: :franchise_id, on_delete: :cascade
    add_foreign_key :user_franchise_conquests, :user_game_completions, column: :completion_id,
      primary_key: :completion_id, on_delete: :nullify
  end
end
