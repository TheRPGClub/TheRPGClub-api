# frozen_string_literal: true

# A GOTY Vote's year, derived phase and dates, the shape GET /goty_votes
# lists. `phase` is the server's verdict at render time (upcoming ->
# nominating -> voting -> closed [-> runoff -> closed] [-> tie] -> decided),
# so clients never re-derive it from the timestamps.
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
end
