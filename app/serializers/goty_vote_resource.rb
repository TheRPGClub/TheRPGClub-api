# frozen_string_literal: true

# One GOTY Vote with its three Awards, in Goty::AWARDS order. Each Award's
# `ballot` is its games (the GameSummaryResource shape): for now the live
# ballots from Goty::Ballots, so Game of the Year stays empty until
# nominations land.
class GotyVoteResource < GotyVoteSummaryResource
  attribute :awards do |vote|
    ballots = Goty::Ballots.for(vote.year)
    ids = ballots.values.flatten.uniq
    games = ids.empty? ? {} : GamedbGame.where(game_id: ids).preload(:images).index_by(&:game_id)
    ballots.map do |award, game_ids|
      { award: award, name: Goty.award_name(award),
        ballot: game_ids.filter_map { |id| games[id] }.map { |game| GameSummaryResource.new(game).serializable_hash } }
    end
  end
end
