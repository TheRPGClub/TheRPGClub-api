# frozen_string_literal: true

# A GOTY Vote's year, derived phase and dates, the shape GET /goty_votes
# lists. `phase` is the server's verdict at render time (upcoming ->
# nominating -> voting -> closed [-> runoff -> closed] [-> tie] -> decided),
# so clients never re-derive it from the timestamps. `winners` lists each
# Award's winner in Award order once the year is decided (empty before,
# even if a runoff left some Awards already won); preload `winners: { game:
# :images }` when listing.
class GotyVoteSummaryResource
  include BaseResource

  attributes :year, :nominations_open_at, :voting_opens_at, :voting_closes_at, :closed_at,
             :runoff_opens_at, :runoff_closes_at, :runoff_closed_at, :decided_at

  attribute :name do |vote|
    "GOTY Vote #{vote.year}"
  end

  attribute :phase do |vote|
    vote.phase
  end

  attribute :nominations_open do |vote|
    vote.nominations_open?
  end

  attribute :voting_open do |vote|
    vote.voting_open?
  end

  attribute :runoff_open do |vote|
    vote.runoff_open?
  end

  attribute :winners do |vote|
    next [] if vote.decided_at.nil?

    vote.winners.sort_by { |winner| Goty::AWARDS.keys.index(winner.award) }.map do |winner|
      { award: winner.award, name: Goty.award_name(winner.award), gamedb_game_id: winner.gamedb_game_id,
        decided_by: winner.decided_by, game: GameSummaryResource.new(winner.game).serializable_hash }
    end
  end
end
