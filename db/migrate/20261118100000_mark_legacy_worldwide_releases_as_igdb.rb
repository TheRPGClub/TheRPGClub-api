# frozen_string_literal: true

# Release Calendar (api#389, owner decision on review-api #1): before the IGDB
# region fix (api#393) every imported Release was stored as Worldwide, and
# api#390 backfilled them all as Manual Releases. A refresh only adopts an
# exact platform + region match, so those rows sat beside IGDB's new regional
# Releases and could still drive announcements.
#
# A Release shaped like the old importer's (Worldwide, no `format`, no `notes`,
# on a game with an IGDB id) becomes an IGDB Release, so the next refresh
# (`gamedb:refresh_releases` on deploy, then the weekly job) updates it or
# replaces it with IGDB's regional Releases. Completionator Releases carry
# notes and staff Releases a format, so both stay Manual.
#
# Plain SQL: no model classes, so later model changes cannot break it.
class MarkLegacyWorldwideReleasesAsIgdb < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE gamedb_releases r
         SET source = 'igdb'
        FROM gamedb_regions g, gamedb_games game
       WHERE g.region_id = r.region_id
         AND game.game_id = r.game_id
         AND r.source = 'manual'
         AND g.region_code = 'WW'
         AND r.format IS NULL
         AND r.notes IS NULL
         AND game.igdb_id IS NOT NULL
    SQL
  end

  # Deliberately a no-op: once a refresh has run, the marked rows cannot be
  # told apart from Releases the refresh itself wrote, and turning those Manual
  # would freeze them. Rolling back leaves every Release as it is.
  def down; end
end
