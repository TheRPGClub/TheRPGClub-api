# frozen_string_literal: true

# A GOTM / Non-RPG GOTM nomination vote with its embedded voter and game
# (#173). The
# two backing tables (`gotm_votes`, `nr_gotm_votes`) share an identical shape,
# so one resource serves both endpoints.
#
# This is the IDENTIFIED vote shape — it names the voter — so VotesController
# only renders it to admin/service while a round's voting window is open, to
# the voter for their own votes, and to everyone once voting has ended (votes
# are anonymous until then; anonymous counts are served by VoteTallyResource).
# The voter is embedded via UserSummaryResource and the game via
# GameSummaryResource; either may be `null` since the columns are unenforced
# by a FK, like the nomination tables.
class VoteResource
  include BaseResource

  attributes :vote_id, :round_number, :user_id, :nomination_id,
             :gamedb_game_id, :voted_at

  one :user, resource: UserSummaryResource
  one :game, resource: GameSummaryResource
end
