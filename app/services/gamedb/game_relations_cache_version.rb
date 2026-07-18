# frozen_string_literal: true

module Gamedb
  # A single cache-backed version counter that invalidates every game's cached
  # relations_data (GamesController#relations_data) when something that isn't
  # reflected by any single game's own `updated_at` changes: a GOTM/NR-GOTM
  # entry (create/reassign/destroy) or a manual game image (create/update/
  # destroy). Both can appear in another game's cached `alternates` slice
  # (gotm_won/nr_gotm_won, cover/art/logo URLs) without touching that game's
  # row. Coarse by design, mirroring the `taxonomy_version` pattern in
  # TaxonomyEndpoints: any bump invalidates every game's relations cache, but
  # these are infrequent admin/bot writes against a read-mostly cache, so the
  # extra invalidation is cheap relative to always querying alternates' live
  # state per request.
  class GameRelationsCacheVersion
    CACHE_KEY = "game_relations_version"

    def self.current
      Rails.cache.fetch(CACHE_KEY) { 1 }
    end

    def self.bump!
      Rails.cache.write(CACHE_KEY, current + 1)
    end
  end
end
