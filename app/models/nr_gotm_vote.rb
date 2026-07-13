# frozen_string_literal: true

# A user's vote on a Non-RPG GOTM nomination (#172) — the Non-RPG counterpart of
# GotmVote. Same shape; see GotmVote for the rationale on the denormalized
# game column and the optional, unenforced associations.
class NrGotmVote < ApplicationRecord
  self.table_name = "nr_gotm_votes"
  self.primary_key = "vote_id"

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    optional: true,
    inverse_of: :nr_gotm_votes
  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    optional: true,
    inverse_of: :nr_gotm_votes
  belongs_to :nomination,
    class_name: "NrGotmNomination",
    foreign_key: :nomination_id,
    primary_key: :nomination_id,
    optional: true,
    inverse_of: :votes

  # NOT NULL columns; presence-validated so a malformed write returns 422
  # rather than a raw NotNullViolation 500.
  validates :round_number, :user_id, :nomination_id, :gamedb_game_id, presence: true
  # Mirrors the ux_nr_gotm_votes_round_user_game unique index — one vote per
  # game per user per round (the backstop behind the cast service's toggle
  # logic).
  validates :gamedb_game_id, uniqueness: { scope: %i[round_number user_id] }
end
