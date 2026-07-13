# frozen_string_literal: true

# Serializes a BotVotingInfo (all columns), plus the derived voting-window
# state so clients can render countdowns without re-implementing the default
# Friday-to-Sunday deadline rule (which is timezone-sensitive): the raw
# `next_vote_at` is when nominations close and voting opens, `vote_deadline`
# is the effective end of voting (the `vote_ends_at` override or the computed
# default, normalized to UTC), and the two booleans are the server's verdict
# at render time.
class VotingInfoResource
  include BaseResource

  columns_of BotVotingInfo

  attribute :vote_deadline do |info|
    info.vote_deadline&.utc
  end

  attribute :voting_open do |info|
    info.voting_open?
  end

  attribute :voting_ended do |info|
    info.voting_ended?
  end
end
