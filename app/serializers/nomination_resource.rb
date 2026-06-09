# frozen_string_literal: true

# A GOTM / Non-RPG GOTM nomination with its embedded nominator and game (bot
# parity, #40). The two backing tables (`gotm_nominations`,
# `nr_gotm_nominations`) share an identical shape, so one resource serves both
# endpoints.
#
# Like the journal serializers (#39) these endpoints are new, so there is no
# prior consumer to audit against: the full meaningful contract is exposed —
# identity (`nomination_id`, `round_number`, `user_id`, `gamedb_game_id`), the
# `reason` free-text, and the `nominated_at` timestamp. The nominator is
# embedded via UserSummaryResource (the shared, consumer-audited user shape)
# and the game via GameSummaryResource; either may be `null` since the
# columns are bot-sourced and unenforced by a FK.
class NominationResource
  include BaseResource

  attributes :nomination_id, :round_number, :user_id, :gamedb_game_id,
             :reason, :nominated_at

  one :user, resource: UserSummaryResource
  one :game, resource: GameSummaryResource
end
