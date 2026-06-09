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
end
