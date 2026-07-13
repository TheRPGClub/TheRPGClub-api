# frozen_string_literal: true

# A user's vote on a GOTM nomination for a voting round (#172). Votes reference the
# specific nomination they were cast on and denormalize its game so the
# one-vote-per-game rule can be enforced without a join (two nominations of
# the same game count as one votable game). Like the nomination tables, no FK
# constraints back the `user_id` / `gamedb_game_id` / `nomination_id` columns,
# so the associations are optional and may resolve to nil.
#
# Casting goes through Voting::CastVote, which owns the toggle / evict / cap
# rules; this model only mirrors the DB constraints.
class GotmVote < ApplicationRecord
  self.table_name = "gotm_votes"
  self.primary_key = "vote_id"

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    optional: true,
    inverse_of: :gotm_votes
  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    optional: true,
    inverse_of: :gotm_votes
  belongs_to :nomination,
    class_name: "GotmNomination",
    foreign_key: :nomination_id,
    primary_key: :nomination_id,
    optional: true,
    inverse_of: :votes

  # NOT NULL columns; presence-validated so a malformed write returns 422
  # rather than a raw NotNullViolation 500.
  validates :round_number, :user_id, :nomination_id, :gamedb_game_id, presence: true
  # Mirrors the ux_gotm_votes_round_user_game unique index — one vote per game
  # per user per round (the backstop behind the cast service's toggle logic).
  validates :gamedb_game_id, uniqueness: { scope: %i[round_number user_id] }
end
