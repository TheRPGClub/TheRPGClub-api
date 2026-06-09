# frozen_string_literal: true

# The reusable embedded-game shape, matching `GamedbGame#as_json`:
#   - every column except `total_rating`
#   - the derived image URLs (`cover_url` / `art_url` / `logo_url`)
#
# Unlike GameResource it omits `gotm_won` / `nr_gotm_won`: those are SQL aliases
# only selected by the `without_images` scope. Games embedded in user-scoped
# entries are loaded through `preload(:game)` (a plain all-columns select) and
# never carry the aliases, so reading them here would raise.
class GameSummaryResource
  include BaseResource

  columns_of GamedbGame, except: %w[total_rating]
  attributes :cover_url, :art_url, :logo_url
end
