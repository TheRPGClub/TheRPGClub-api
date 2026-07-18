# frozen_string_literal: true

module Gamedb
  # A single cache-backed version counter that invalidates every game's cached
  # relations_data (GamesController#relations_data) when a GameResource field
  # (title, description, images, gotm_won/nr_gotm_won, ...) changes in a way
  # that isn't reflected by that specific game's own `updated_at` as seen by
  # *other* games embedding it in their cached `alternates` slice: a manual
  # edit (GamesController#update), an IGDB re-import (IgdbGameImporter), a
  # GOTM/NR-GOTM entry (create/reassign/destroy), or a game image
  # (create/update/destroy, manual or IGDB-driven). Coarse by design,
  # mirroring the `taxonomy_version` pattern in TaxonomyEndpoints: any bump
  # invalidates every game's relations cache, but these are infrequent
  # admin/bot writes against a read-mostly cache, so the extra invalidation is
  # cheap relative to always querying alternates' live state per request.
  class GameRelationsCacheVersion
    CACHE_KEY = "game_relations_version"

    def self.current
      Rails.cache.fetch(CACHE_KEY) { 1 }
    end

    # Rails.cache.increment is atomic on every store this app uses in
    # practice (solid_cache's DB-row-locked adjust in production,
    # MemoryStore's mutex in development) -- unlike a read-then-write
    # `write(current + 1)`, which can silently drop an invalidation when two
    # writers bump concurrently.
    def self.bump!
      Rails.cache.increment(CACHE_KEY, 1)
    end
  end
end
