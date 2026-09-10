# frozen_string_literal: true

# The consumer-audited review allowlist (#36), shared by the standalone review
# shape (ReviewResource) and the game-/user-embedded variants
# (ReviewEntryResource / ReviewUserEntryResource).
#
# The web frontend reads `review_id`, `user_id`, `gamedb_game_id`, `rating`,
# `body`, `facets` and `created_at`. `facets` is here rather than in the full
# `as_json` shape alone because the listing cards on the game and member pages
# render the scorecard. `is_shared` is a write-only input (never read back) and
# `updated_at` is unused, so both are dropped from output. No Discord-bot-only
# review fields are known.
module ReviewFields
  extend ActiveSupport::Concern

  included do
    attributes :review_id, :user_id, :gamedb_game_id, :rating, :body, :facets, :created_at
  end
end
