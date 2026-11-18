# frozen_string_literal: true

# Release Calendar (api#390, ADR 0010): every Release records whether it is an
# IGDB Release (kept in step by the in-place IGDB refresh) or a Manual Release
# (added by staff or another import, never touched by a refresh). Existing
# Releases are backfilled as Manual Releases through the column default; a
# refresh adopts one when IGDB reports the same game, platform and region.
class AddSourceToGamedbReleases < ActiveRecord::Migration[8.1]
  def change
    add_column :gamedb_releases, :source, :string, limit: 10, null: false, default: "manual"
    add_check_constraint :gamedb_releases, "source IN ('igdb', 'manual')", name: "ck_gamedb_releases_source"
  end
end
