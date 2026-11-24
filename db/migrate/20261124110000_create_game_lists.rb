# frozen_string_literal: true

# Game Lists (GLOSSARY.md, "Game List"; spec api#442, ticket api#446): named
# lists of GameDB games a member keeps around any theme, or the club owns.
#
#   owner_user_id            the member who owns it; null for a club list.
#                            A member's lists go with their record.
#   visibility               members (any member reads it) or private (only
#                            its owner, never staff). A club list is always
#                            members.
#   sort                     how it is shown: ranked (by position),
#                            alphabetical (by title) or added (newest first)
#   taken_over_from_user_id, the member a club list was taken over from, and
#   taken_over_at            when (ticket api#448); null otherwise
#
# Entries: one row per game per list (the primary key), with its place in
# the ranked order, an optional note and when it was added. A list holds at
# most 500 (GameList::ENTRIES_MAX, checked under the list's lock). Entries
# go with their list, and with their game.
class CreateGameLists < ActiveRecord::Migration[8.1]
  def change
    create_table :game_lists do |t|
      t.string :owner_user_id, limit: 30
      t.string :name, limit: 100, null: false
      t.string :description, limit: 500
      t.string :visibility, limit: 8, null: false, default: "members"
      t.string :sort, limit: 12, null: false, default: "ranked"
      t.string :taken_over_from_user_id, limit: 30
      t.timestamptz :taken_over_at
      t.timestamps

      t.check_constraint "visibility IN ('members', 'private')", name: "ck_game_lists_visibility"
      t.check_constraint "sort IN ('ranked', 'alphabetical', 'added')", name: "ck_game_lists_sort"
      t.check_constraint "owner_user_id IS NOT NULL OR visibility = 'members'", name: "ck_game_lists_club_members"
      t.check_constraint "(taken_over_from_user_id IS NULL) = (taken_over_at IS NULL)",
        name: "ck_game_lists_taken_over_together"
    end
    add_index :game_lists, %i[owner_user_id updated_at], name: "ix_game_lists_owner_updated"
    add_index :game_lists, :updated_at, name: "ix_game_lists_updated"
    add_foreign_key :game_lists, :rpg_club_users, column: :owner_user_id, primary_key: :user_id,
      on_delete: :cascade, name: "fk_game_lists_owner"
    add_foreign_key :game_lists, :rpg_club_users, column: :taken_over_from_user_id, primary_key: :user_id,
      on_delete: :nullify, name: "fk_game_lists_taken_over_from"

    create_table :game_list_entries, primary_key: %i[game_list_id game_id] do |t|
      t.bigint :game_list_id, null: false
      t.bigint :game_id, null: false
      t.integer :position, null: false
      t.string :note, limit: 280
      t.timestamptz :added_at, null: false, default: -> { "CURRENT_TIMESTAMP" }

      t.check_constraint "position >= 1", name: "ck_game_list_entries_position"
    end
    add_index :game_list_entries, %i[game_list_id position], name: "ix_game_list_entries_position"
    add_index :game_list_entries, :game_id, name: "ix_game_list_entries_game"
    add_foreign_key :game_list_entries, :game_lists, on_delete: :cascade, name: "fk_game_list_entries_list"
    add_foreign_key :game_list_entries, :gamedb_games, column: :game_id, primary_key: :game_id,
      on_delete: :cascade, name: "fk_game_list_entries_game"
  end
end
