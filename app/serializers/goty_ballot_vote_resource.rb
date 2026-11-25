# frozen_string_literal: true

# A member's vote in one Award of a GOTY Vote, as the cast response returns
# it (the voter's own, or the service's on their behalf).
class GotyBallotVoteResource
  include BaseResource

  attributes :id, :year, :award, :user_id, :gamedb_game_id, :runoff, :voted_at

  one :game, resource: GameSummaryResource
end
