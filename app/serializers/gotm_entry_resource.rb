# frozen_string_literal: true

# Serializes a GotmEntry, matching the legacy `GotmEntry#as_json`: all entry
# columns plus an optional embedded `game`.
#
# The legacy override embedded `game` only when `association(:game).loaded?` (a
# probe of how the controller built the scope). That decision now lives in the
# controller, which passes `include_game: true` via Alba params when it has
# eager-loaded `game: :images`; the embed is gated on that flag, so the `game`
# key is omitted entirely (not rendered as `null`) when the flag is absent.
#
# The embed uses GameSummaryResource — the reusable all-columns-except-rating
# shape that matches `GamedbGame#as_json` on a plain-loaded record. GameResource
# is wrong here: it re-declares the `gotm_won`/`nr_gotm_won` SQL aliases, which
# only exist on records loaded through `GamedbGame.without_images`. GOTM games
# are loaded via `preload(game: :images)` (a plain all-columns select), so
# GameResource would raise on the missing aliases.
class GotmEntryResource
  include BaseResource

  columns_of GotmEntry
  one :game, resource: GameSummaryResource, if: proc { params[:include_game] }
end
