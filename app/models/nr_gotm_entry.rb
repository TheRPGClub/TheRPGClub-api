# frozen_string_literal: true

class NrGotmEntry < ApplicationRecord
  self.table_name = "nr_gotm_entries"
  self.primary_key = "nr_gotm_id"

  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    optional: true,
    inverse_of: :nr_gotm_entries

  # NOT NULL columns; presence-validated so a malformed create returns 422
  # rather than a raw NotNullViolation 500.
  validates :round_number, :month_year, :game_index, presence: true
  # Required on create per the bot's write contract (#98). Left unconstrained on
  # update so a PATCH of other fields never trips on a legacy NULL row.
  validates :gamedb_game_id, presence: true, on: :create
  # Mirrors the ux_nr_gotm_entries_rnd_idx unique index — one row per game slot
  # per round.
  validates :game_index, uniqueness: { scope: :round_number }
end
