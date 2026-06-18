# frozen_string_literal: true

# A Non-RPG GOTM nomination (bot parity, #40) — the Non-RPG counterpart of
# GotmNomination. Same shape; see GotmNomination for the rationale on the
# optional, unenforced `user`/`game` associations.
class NrGotmNomination < ApplicationRecord
  self.table_name = "nr_gotm_nominations"
  self.primary_key = "nomination_id"

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    optional: true,
    inverse_of: :nr_gotm_nominations
  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    optional: true,
    inverse_of: :nr_gotm_nominations

  # NOT NULL columns; presence-validated so a malformed upsert (#97) returns 422
  # rather than a raw NotNullViolation 500. Unlike GOTM, `gamedb_game_id` is
  # NOT NULL on the NR-GOTM table, so it is required here too.
  validates :round_number, :user_id, :gamedb_game_id, presence: true
  # Mirrors the ux_nr_gotm_noms_round_user unique index — one nomination per
  # user per round (the conflict target the upsert resolves against).
  validates :user_id, uniqueness: { scope: :round_number }
end
