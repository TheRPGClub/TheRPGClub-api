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
end
