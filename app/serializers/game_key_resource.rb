# frozen_string_literal: true

# Serializes a game key for the giveaway (bot parity, #42).
#
# The `key_value` secret is deliberately omitted from list responses: it is
# rendered only when the resource is built with `params: { reveal_key: true }`,
# which the controller passes solely in the response to a successful claim, so
# the secret reaches only the claimer. Everything else — identity, the donor
# and claim state, and the donor's notify-on-claim flag — is always exposed.
#
# `game` embeds the linked GamedbGame (title + cover/art/logo URLs, via the
# shared GameSummaryResource) so a frontend can showcase the key with the same
# game card it uses for favorites/backlog. It is `null` for keys whose game
# isn't in `gamedb_games` (they carry only the free-text `game_title`), which is
# why `game_title` is always kept as the fallback label.
class GameKeyResource
  include BaseResource

  attributes :key_id, :game_title, :platform, :region, :gamedb_game_id, :donor_user_id,
             :claimed_by_user_id, :claimed_at, :donor_notify_on_claim,
             :created_at, :updated_at

  attributes :key_value, if: proc { params[:reveal_key] }

  one :game, resource: GameSummaryResource
end
