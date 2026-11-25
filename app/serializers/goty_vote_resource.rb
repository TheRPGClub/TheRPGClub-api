# frozen_string_literal: true

# One GOTY Vote with its three Awards, in Goty::AWARDS order, each with its
# ballot and standings (Goty::Standings): the cap, the viewer's own votes,
# the tally as far as the viewer may see it, the full result once decided,
# and the winner. Pass `params: { viewer_id:, staff: }`.
class GotyVoteResource < GotyVoteSummaryResource
  attributes :candidates_frozen_at, :pending_ties, :runoff_ties

  attribute :awards do |vote|
    Goty::Standings.awards(vote, viewer_id: params[:viewer_id], staff: params[:staff] || false)
  end
end
