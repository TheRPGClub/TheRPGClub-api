# frozen_string_literal: true

# Per-game journal feature (bot parity, #39). The journal entries table was
# Oracle-only in the Discord bot and did not come across in the Postgres
# migration; this recreates it. Every entry is public — there is no
# private/visibility concept — so the bot's `is_public` flag and the per-game
# preferences table (`is_enabled` / `default_is_public`) are intentionally
# omitted. `entry_title` is optional (modal-capped at 120 chars in the bot),
# `entry_body` is required.
class CreateUserGameJournalEntries < ActiveRecord::Migration[8.1]
  def up
    return if table_exists?(:user_game_journal_entries)

    create_table :user_game_journal_entries, primary_key: :entry_id do |table|
      table.string :user_id, limit: 50, null: false
      table.bigint :gamedb_game_id, null: false
      table.string :entry_title, limit: 120
      table.text :entry_body, null: false
      table.datetime :created_at, precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
      table.datetime :updated_at, precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
    end

    add_index :user_game_journal_entries, %i[user_id gamedb_game_id],
              name: "ix_user_game_journal_entries_user_game"
    add_index :user_game_journal_entries, :gamedb_game_id,
              name: "ix_user_game_journal_entries_game"
    add_index :user_game_journal_entries, :user_id,
              name: "ix_user_game_journal_entries_user"

    add_foreign_key :user_game_journal_entries,
                    :gamedb_games,
                    column: :gamedb_game_id,
                    primary_key: :game_id,
                    name: "fk_user_game_journal_entries_gamedb"
    add_foreign_key :user_game_journal_entries,
                    :rpg_club_users,
                    column: :user_id,
                    primary_key: :user_id,
                    name: "fk_user_game_journal_entries_user"
  end

  def down
    drop_table :user_game_journal_entries, if_exists: true
  end
end
