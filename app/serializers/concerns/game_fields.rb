# frozen_string_literal: true

# The consumer-audited game allowlist (#36), shared by the embedded game shape
# (GameSummaryResource) and the games#index/show resource (GameResource).
#
# The web frontend reads `game_id`, `title`, `description`, `igdb_url`,
# `initial_release_date` and the derived image URLs. `igdb_id`, `slug` and
# `logo_url` are kept because they are plausible Discord bot fields (the bot's
# source is not auditable — see issue #36); everything else `GamedbGame`
# exposes (`collection_id`, `parent_*`, `thumbnail_*`,
# `created_at`/`updated_at`) is dropped.
#
# This omits `gotm_won`/`nr_gotm_won`: those are SQL aliases selected only by
# the `without_images` scope. GameResource adds them; embedded games (loaded via
# `preload(:game)`, a plain all-columns select) never carry them, so reading
# them there would raise.
module GameFields
  extend ActiveSupport::Concern

  included do
    attributes :game_id, :title, :description, :igdb_id, :slug,
               :igdb_url, :initial_release_date
    attributes :cover_url, :art_url, :logo_url
  end
end
