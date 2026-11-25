# frozen_string_literal: true

# The bot's outbox carries the GOTY Vote's posts too (spec api#471, ticket
# api#475): an event belongs to a GOTM round (`round_number`) or to a GOTY
# Vote (`goty_year`), exactly one of the two, and each GOTY Vote queues a
# kind once.
class AddGotyYearToVotingEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :voting_events, :goty_year, :integer
    change_column_null :voting_events, :round_number, true
    add_index :voting_events, %i[goty_year kind], unique: true, name: "ux_voting_events_goty_year_kind"
    add_check_constraint :voting_events, "(round_number IS NULL) <> (goty_year IS NULL)",
      name: "ck_voting_events_round_or_goty_year"
    add_foreign_key :voting_events, :goty_votes, column: :goty_year, primary_key: :year, on_delete: :cascade
  end
end
