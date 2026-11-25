# frozen_string_literal: true

# A member's vote for a candidate in one Award of a year's GOTY Vote (spec
# api#471), on the main ballot or, with `runoff`, the Award's runoff. Votes
# are per game: at most one per member, Award, ballot and game. Casting goes
# through Goty::CastVote, which applies the shared Voting::CastRules.
class GotyBallotVote < ApplicationRecord
  belongs_to :goty_vote, foreign_key: :year, primary_key: :year, inverse_of: :ballot_votes
  belongs_to :user, -> { without_images },
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    inverse_of: :goty_ballot_votes
  belongs_to :game, class_name: "GamedbGame", foreign_key: :gamedb_game_id, inverse_of: :goty_ballot_votes

  validates :award, inclusion: { in: Goty::AWARDS.keys }
  validates :gamedb_game_id, uniqueness: { scope: %i[year award runoff user_id] }
end
