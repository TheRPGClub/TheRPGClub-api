# frozen_string_literal: true

# One GOTY Vote with its three Awards, in Goty::AWARDS order, each with its
# ballot and standings (Goty::Standings): the cap, the viewer's own votes,
# the tally as far as the viewer may see it, the full result once decided,
# and the winner. While the vote is upcoming it also carries the Year So
# Far's `club_releases` (Goty::ClubReleases; spec api#481), left out in
# every other phase. Pass `params: { viewer_id:, staff: }`.
class GotyVoteResource < GotyVoteSummaryResource
  attributes :candidates_frozen_at, :pending_ties, :runoff_ties

  attribute :awards do |vote|
    Goty::Standings.awards(vote, viewer_id: params[:viewer_id], staff: params[:staff] || false)
  end

  attribute :club_releases, if: proc { |vote| vote.phase == "upcoming" } do |vote|
    Goty::ClubReleases.for(vote.year).map do |row|
      { game: GameSummaryResource.new(row.game).serializable_hash, members_played: row.members_played }
    end
  end
end
