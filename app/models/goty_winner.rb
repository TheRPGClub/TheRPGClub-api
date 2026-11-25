# frozen_string_literal: true

# The game that won one Award of a year's GOTY Vote (spec api#471), and how:
# `vote` (the tally), `runoff`, `admin` (after a runoff tied again) or
# `uncontested` (the Award's only candidate). One per year and Award; a game
# may win several Awards.
class GotyWinner < ApplicationRecord
  belongs_to :goty_vote, foreign_key: :year, primary_key: :year, inverse_of: :winners
  belongs_to :game, class_name: "GamedbGame", foreign_key: :gamedb_game_id, inverse_of: :goty_winners

  validates :award, inclusion: { in: Goty::AWARDS.keys }, uniqueness: { scope: :year }
  validates :decided_by, inclusion: { in: Voting::Decide::DECIDED_BY }
end
