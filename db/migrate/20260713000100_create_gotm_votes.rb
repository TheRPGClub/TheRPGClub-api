# frozen_string_literal: true

class CreateGotmVotes < ActiveRecord::Migration[8.1]
  def up
    return if table_exists?(:gotm_votes)

    create_table :gotm_votes, primary_key: :vote_id do |table|
      table.bigint :round_number, null: false
      table.string :user_id, limit: 64, null: false
      table.bigint :nomination_id, null: false
      table.bigint :gamedb_game_id, null: false
      table.datetime :voted_at, precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
    end

    # One vote per game per user per round — the DB backstop behind the
    # cast service's toggle-by-game logic.
    add_index :gotm_votes, %i[round_number user_id gamedb_game_id],
              unique: true,
              name: "ux_gotm_votes_round_user_game"
    # Serves the per-nomination tally GROUP BY and the vote cleanup when a
    # nomination is deleted.
    add_index :gotm_votes, %i[round_number nomination_id],
              name: "ix_gotm_votes_round_nomination"
  end

  def down
    drop_table :gotm_votes, if_exists: true
  end
end
