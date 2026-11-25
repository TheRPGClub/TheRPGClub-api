# frozen_string_literal: true

# Award voting for the GOTY Vote (spec api#471, ticket api#474): each
# Award's candidates frozen at voting open, members' votes on them (main
# ballot and runoff), and each Award's winner with how it was decided.
# `candidates_frozen_at` marks the freeze, so it runs once.
class CreateGotyAwardVoting < ActiveRecord::Migration[8.1]
  AWARDS = "award IN ('gotm', 'nr_gotm', 'game_of_the_year')"

  def change
    add_column :goty_votes, :candidates_frozen_at, :datetime

    create_table :goty_candidates do |t|
      t.integer :year, null: false
      t.string :award, limit: 32, null: false
      t.bigint :gamedb_game_id, null: false
      t.integer :position, null: false
      t.timestamps
    end
    add_index :goty_candidates, %i[year award gamedb_game_id], unique: true, name: "ux_goty_candidates_year_award_game"
    add_check_constraint :goty_candidates, AWARDS, name: "ck_goty_candidates_award"

    create_table :goty_ballot_votes do |t|
      t.integer :year, null: false
      t.string :award, limit: 32, null: false
      t.string :user_id, limit: 64, null: false
      t.bigint :gamedb_game_id, null: false
      t.boolean :runoff, null: false, default: false
      t.datetime :voted_at, precision: 6, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end
    add_index :goty_ballot_votes, %i[year award runoff user_id gamedb_game_id], unique: true,
      name: "ux_goty_ballot_votes_year_award_runoff_user_game"
    add_check_constraint :goty_ballot_votes, AWARDS, name: "ck_goty_ballot_votes_award"

    create_table :goty_winners do |t|
      t.integer :year, null: false
      t.string :award, limit: 32, null: false
      t.bigint :gamedb_game_id, null: false
      t.string :decided_by, limit: 16, null: false
      t.timestamps
    end
    add_index :goty_winners, %i[year award], unique: true, name: "ux_goty_winners_year_award"
    add_index :goty_winners, :gamedb_game_id, name: "ix_goty_winners_game"
    add_check_constraint :goty_winners, AWARDS, name: "ck_goty_winners_award"
    add_check_constraint :goty_winners, "decided_by IN ('vote', 'runoff', 'admin', 'uncontested')",
      name: "ck_goty_winners_decided_by"

    %i[goty_candidates goty_ballot_votes goty_winners].each do |table|
      add_foreign_key table, :goty_votes, column: :year, primary_key: :year, on_delete: :cascade
      add_foreign_key table, :gamedb_games, column: :gamedb_game_id, primary_key: :game_id, on_delete: :cascade
    end
    add_foreign_key :goty_ballot_votes, :rpg_club_users, column: :user_id, primary_key: :user_id, on_delete: :cascade
  end
end
