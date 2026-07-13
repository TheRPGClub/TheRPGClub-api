# frozen_string_literal: true

# A GOTM nomination (bot parity, #40): who nominated which game for a voting
# round, and why. The winners live in GotmEntry; this is the field of
# candidates behind each round. No FK constraints back the `user_id` /
# `gamedb_game_id` columns (bot-sourced data), so both associations are
# optional and may resolve to nil.
class GotmNomination < ApplicationRecord
  self.table_name = "gotm_nominations"
  self.primary_key = "nomination_id"

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    optional: true,
    inverse_of: :gotm_nominations
  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    optional: true,
    inverse_of: :gotm_nominations
  has_many :votes,
    class_name: "GotmVote",
    foreign_key: :nomination_id,
    primary_key: :nomination_id,
    dependent: nil,
    inverse_of: :nomination

  # NOT NULL columns; presence-validated so a malformed upsert (#97) returns 422
  # rather than a raw NotNullViolation 500. `gamedb_game_id` is nullable on the
  # GOTM table (unlike NR-GOTM), so it is not required here.
  validates :round_number, :user_id, presence: true
  # Mirrors the ux_gotm_nominations_round_user unique index — one nomination per
  # user per round (the conflict target the upsert resolves against).
  validates :user_id, uniqueness: { scope: :round_number }
end
