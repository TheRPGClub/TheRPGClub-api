# frozen_string_literal: true

# The GOTY Vote (spec api#471): one row per year, keyed by the year it
# decides. Its phase is derived from these timestamps at read time, as for
# voting_rounds; the lifecycle sweep only performs the side effects.
class CreateGotyVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :goty_votes, primary_key: :year, id: :integer, default: nil do |t|
      t.datetime :nominations_open_at, precision: 6, null: false
      # Game of the Year nominations close and all three Awards open for
      # voting at the same instant.
      t.datetime :voting_opens_at, precision: 6, null: false
      t.datetime :voting_closes_at, precision: 6, null: false
      # The one runoff for the Awards the main vote left tied.
      t.datetime :runoff_opens_at, precision: 6
      t.datetime :runoff_closes_at, precision: 6
      t.datetime :runoff_closed_at, precision: 6
      # Awards still awaiting a decision, and the runoff's original ballot:
      # { "gotm" => [gamedb_game_id, ...], "game_of_the_year" => [...] }.
      t.jsonb :pending_ties, null: false, default: {}
      t.jsonb :runoff_ties, null: false, default: {}
      t.datetime :closed_at, precision: 6
      t.datetime :decided_at, precision: 6
      t.timestamps
    end
  end
end
