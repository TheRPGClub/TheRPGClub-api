# frozen_string_literal: true

# A single row of a round's anonymous vote tally (VotesController#*_tally,
# #173):
# one nomination plus how many votes it holds — no voter identities, so it is
# safe to serve while the voting window is open. Not a plain model record —
# the controller hands in the grouped/aggregated rows (`nomination_id` and
# `gamedb_game_id` grouped off the votes table plus the `COUNT(*)`
# `vote_count` alias), read the same way AvatarHistoryCountResource serializes
# its grouped aggregates. Nominations with zero votes have no row here —
# callers merge against the round's nominations list.
class VoteTallyResource
  include BaseResource

  attributes :nomination_id, :gamedb_game_id

  attribute :vote_count do |row|
    row["vote_count"].to_i
  end
end
