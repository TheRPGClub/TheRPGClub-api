# frozen_string_literal: true

# Challenges (GLOSSARY.md, "Run"; spec #376, ticket #378): Runs and their
# progress, on the minimal challenge_runs table ticket #377 created.
#
# A Run of a Seasonal Challenge records the Season it belongs to as its
# concrete first and last day (club time zone), which is its window; an
# Always Open Run's window runs from its start to the Challenge's end date.
# `ended_at` is when it became Finished, Expired or Abandoned.
#
# challenge_run_entries holds one row per game counted on a Run: In Progress
# (in the member's Now Playing) or Cleared (by a Game Completion dated inside
# the window, kept in `completion_id`). Slots (#381) and past play (#382) add
# their own columns (slot year, picked by hand).
class AddProgressToChallengeRuns < ActiveRecord::Migration[8.1]
  def change
    change_table :challenge_runs, bulk: true do |t|
      t.date :season_starts_on
      t.date :season_ends_on
      t.timestamptz :ended_at
      t.check_constraint "(season_starts_on IS NULL) = (season_ends_on IS NULL)", name: "ck_challenge_runs_season"
    end
    add_index :challenge_runs, %i[challenge_id status], name: "ix_challenge_runs_challenge_status"

    create_table :challenge_run_entries do |t|
      t.bigint :run_id, null: false
      t.bigint :game_id, null: false
      t.string :state, limit: 16, null: false
      t.bigint :completion_id
      t.date :cleared_on
      t.timestamps

      t.check_constraint "state IN ('in_progress', 'cleared')", name: "ck_challenge_run_entries_state"
    end
    add_index :challenge_run_entries, %i[run_id game_id], unique: true, name: "ux_challenge_run_entries_game"
    add_foreign_key :challenge_run_entries, :challenge_runs, column: :run_id, on_delete: :cascade,
      name: "fk_challenge_run_entries_run"
    add_foreign_key :challenge_run_entries, :gamedb_games, column: :game_id, primary_key: :game_id,
      on_delete: :cascade, name: "fk_challenge_run_entries_game"
    # A Finished Run keeps its Cleared games after the Game Completion goes.
    add_foreign_key :challenge_run_entries, :user_game_completions, column: :completion_id,
      primary_key: :completion_id, on_delete: :nullify, name: "fk_challenge_run_entries_completion"
  end
end
