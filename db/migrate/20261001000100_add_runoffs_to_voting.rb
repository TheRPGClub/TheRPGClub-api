# frozen_string_literal: true

# Tie-breaker runoffs (#259): a category whose main vote ties goes to a member
# vote limited to the tied games instead of waiting on an admin pick.
#
# Runoff votes live beside the main ones, flagged, so the main tally stays
# intact for history. A member already holds a main vote for a tied game, so
# the one-vote-per-game index now includes the flag.
class AddRunoffsToVoting < ActiveRecord::Migration[8.1]
  def change
    change_table :voting_rounds, bulk: true do |t|
      # The runoff window, set when the main vote's tally ties. One runoff per
      # round: a runoff that ties again falls back to an admin pick.
      t.datetime :runoff_opens_at, precision: 6
      t.datetime :runoff_closes_at, precision: 6
      # Set once the runoff's tally has been finalized into winners and/or
      # ties left for an admin.
      t.datetime :runoff_closed_at, precision: 6
      # The runoff's ballot, kept for history: the games each category tied
      # on in the main vote, { "gotm" => [gamedb_game_id, ...] }.
      t.jsonb :runoff_ties, null: false, default: {}
    end

    %w[gotm_votes nr_gotm_votes].each do |table|
      add_column table, :runoff, :boolean, null: false, default: false
      remove_index table, %i[round_number user_id gamedb_game_id], unique: true,
        name: "ux_#{table}_round_user_game"
      add_index table, %i[round_number runoff user_id gamedb_game_id], unique: true,
        name: "ux_#{table}_round_runoff_user_game"
    end
  end
end
