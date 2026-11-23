# frozen_string_literal: true

# The consumer-audited review allowlist (#36), shared by the standalone review
# shape (ReviewResource) and the game-/user-embedded variants
# (ReviewEntryResource / ReviewUserEntryResource).
#
# The web frontend reads `review_id`, `user_id`, `gamedb_game_id`, `rating`
# (the current score once Revisions exist, spec api#430), `original_rating`,
# `revised` (whether it has Published Revisions),
# `title`, `body`, `facets`, `created_at`, `published_at` (the date a
# Review is shown with once Drafts exist, spec api#430) and `edited_at` (the
# "Edited *date*" by the byline, ADR 0013). `facets` is here rather than in
# the full `as_json` shape alone because the listing cards on the game and
# member pages render the scorecard, and `title` for the same reason — the
# cards render it as a headline above the body. `updated_at` is unused, so it
# is dropped from output. No Discord-bot-only review fields are known.
module ReviewFields
  extend ActiveSupport::Concern

  included do
    attributes :review_id, :user_id, :gamedb_game_id
    # The current score (the latest Published Revision's, else the Review's
    # own) and the original take's. Preload `latest_revision`.
    attribute(:rating, &:current_rating)
    attribute(:original_rating, &:rating)
    # Whether it has Published Revisions, so a list can say a newer take
    # exists (the game page's small editor edits only the first).
    attribute(:revised) { |review| !review.latest_revision.nil? }
    attributes :title, :body, :facets, :created_at, :published_at, :edited_at
  end
end
