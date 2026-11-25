# frozen_string_literal: true

# A game on one Award's ballot for a year's GOTY Vote (spec api#471),
# frozen when voting opens (Goty::FreezeCandidates). The tally, the cap and
# the history read these, not the live ballots. `position` keeps the
# ballot's order.
class GotyCandidate < ApplicationRecord
  belongs_to :goty_vote, foreign_key: :year, primary_key: :year, inverse_of: :candidates
  belongs_to :game, class_name: "GamedbGame", foreign_key: :gamedb_game_id, inverse_of: :goty_candidates

  validates :award, inclusion: { in: Goty::AWARDS.keys }
  validates :gamedb_game_id, uniqueness: { scope: %i[year award] }

  scope :ballot, ->(year, award) { where(year: year, award: award.to_s).order(:position) }
end
