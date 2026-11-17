# frozen_string_literal: true

# Challenges (GLOSSARY.md, "Challenges"; spec #376, ticket #377).
#
# A Challenge has a Host, a member (`host_user_id`) or the club itself
# (null), one Challenge Format and a schedule: Always Open, with an optional
# last day (`ends_on`), or Seasonal, with a Season given as start and end
# month and day that repeats every year and may cross the new year.
#
# Each Challenge Format keeps its own settings: the Pool's here as its target
# (`pool_target`, null meaning every game in the Pool) and its definition in
# the challenge_pool_* tables. Slots (#381) and Assignment (#383) add their
# own columns or tables the same way, so the formats never share a column.
#
# A Run (challenge_runs) is one member's attempt. This ticket only needs to
# know whether a Challenge has any, since that locks its rules; Runs and
# their progress arrive in ticket #378.
class CreateChallenges < ActiveRecord::Migration[8.1]
  def change
    create_table :challenges do |t|
      t.string :name, limit: 100, null: false
      t.text :description, null: false, default: ""
      t.string :host_user_id, limit: 30
      t.string :challenge_format, limit: 16, null: false
      t.string :schedule, limit: 16, null: false
      t.date :ends_on
      t.integer :season_start_month, limit: 2
      t.integer :season_start_day, limit: 2
      t.integer :season_end_month, limit: 2
      t.integer :season_end_day, limit: 2
      t.integer :pool_target
      t.boolean :hidden, null: false, default: false
      t.string :created_by, limit: 30
      t.string :updated_by, limit: 30
      t.timestamps

      t.check_constraint "challenge_format IN ('slots', 'pool', 'assignment')", name: "ck_challenges_format"
      t.check_constraint "schedule IN ('always_open', 'seasonal')", name: "ck_challenges_schedule"
      t.check_constraint "(schedule = 'seasonal') = (season_start_month IS NOT NULL AND season_start_day IS NOT NULL " \
        "AND season_end_month IS NOT NULL AND season_end_day IS NOT NULL)", name: "ck_challenges_season"
      t.check_constraint "schedule = 'always_open' OR ends_on IS NULL", name: "ck_challenges_ends_on"
      t.check_constraint "pool_target IS NULL OR pool_target >= 1", name: "ck_challenges_pool_target"
    end
    add_index :challenges, "lower(name)", name: "ix_challenges_lower_name"
    add_index :challenges, :host_user_id, name: "ix_challenges_host"
    add_foreign_key :challenges, :rpg_club_users, column: :host_user_id, primary_key: :user_id,
      on_delete: :nullify, name: "fk_challenges_host"

    # A Pool's definition: the chosen franchises and collections, plus games
    # included or excluded by hand.
    create_table :challenge_pool_franchises, primary_key: %i[challenge_id franchise_id] do |t|
      t.bigint :challenge_id, null: false
      t.bigint :franchise_id, null: false
    end
    add_foreign_key :challenge_pool_franchises, :challenges, on_delete: :cascade,
      name: "fk_challenge_pool_franchises_challenge"
    add_foreign_key :challenge_pool_franchises, :gamedb_franchises, column: :franchise_id, primary_key: :franchise_id,
      on_delete: :cascade, name: "fk_challenge_pool_franchises_franchise"

    create_table :challenge_pool_collections, primary_key: %i[challenge_id collection_id] do |t|
      t.bigint :challenge_id, null: false
      t.bigint :collection_id, null: false
    end
    add_foreign_key :challenge_pool_collections, :challenges, on_delete: :cascade,
      name: "fk_challenge_pool_collections_challenge"
    add_foreign_key :challenge_pool_collections, :gamedb_collections, column: :collection_id,
      primary_key: :collection_id, on_delete: :cascade, name: "fk_challenge_pool_collections_collection"

    create_table :challenge_pool_games, primary_key: %i[challenge_id game_id] do |t|
      t.bigint :challenge_id, null: false
      t.bigint :game_id, null: false
      t.string :inclusion, limit: 8, null: false

      t.check_constraint "inclusion IN ('include', 'exclude')", name: "ck_challenge_pool_games_inclusion"
    end
    add_foreign_key :challenge_pool_games, :challenges, on_delete: :cascade, name: "fk_challenge_pool_games_challenge"
    add_foreign_key :challenge_pool_games, :gamedb_games, column: :game_id, primary_key: :game_id,
      on_delete: :cascade, name: "fk_challenge_pool_games_game"

    # Runs: one member's attempt at a Challenge. Only one Active Run per
    # member per Challenge.
    create_table :challenge_runs do |t|
      t.bigint :challenge_id, null: false
      t.string :user_id, limit: 30, null: false
      t.string :status, limit: 16, null: false, default: "active"
      t.timestamptz :started_at, null: false, default: -> { "statement_timestamp()" }
      t.timestamps

      t.check_constraint "status IN ('active', 'finished', 'expired', 'abandoned')", name: "ck_challenge_runs_status"
    end
    add_index :challenge_runs, %i[challenge_id user_id], unique: true, where: "status = 'active'",
      name: "ux_challenge_runs_one_active"
    add_index :challenge_runs, :user_id, name: "ix_challenge_runs_user"
    add_foreign_key :challenge_runs, :challenges, on_delete: :cascade, name: "fk_challenge_runs_challenge"
    add_foreign_key :challenge_runs, :rpg_club_users, column: :user_id, primary_key: :user_id,
      on_delete: :cascade, name: "fk_challenge_runs_user"
  end
end
