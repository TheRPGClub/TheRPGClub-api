# frozen_string_literal: true

# A Game of the Year nomination with its nominator and game (spec api#471),
# the shape GET /goty_votes/:year/nominations lists. The game carries its
# platforms, as GOTM nominations do, so a nominations board can show them.
class GotyNominationResource
  include BaseResource

  attributes :id, :year, :user_id, :gamedb_game_id, :reason, :nominated_at

  one :user, resource: UserSummaryResource
  one :game, resource: GameWithPlatformsResource
end
