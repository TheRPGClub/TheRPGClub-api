# frozen_string_literal: true

class GamedbRelease < ApplicationRecord
  self.table_name = "gamedb_releases"
  self.primary_key = "release_id"

  # Where a Release comes from (ADR 0008). An IGDB Release is kept in step by
  # the in-place IGDB refresh (Gamedb::ReleaseSync): its date can move and it
  # can be removed. A Manual Release (staff, the Completionator import, any
  # other writer) is never changed or removed by a refresh, only adopted when
  # IGDB reports the same game, platform and region.
  SOURCES = %w[igdb manual].freeze

  enum :source, SOURCES.index_with(&:itself), prefix: true, validate: true

  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :game_id,
    inverse_of: :releases
  belongs_to :platform,
    class_name: "GamedbPlatform",
    foreign_key: :platform_id,
    inverse_of: :releases
  belongs_to :region,
    class_name: "GamedbRegion",
    foreign_key: :region_id,
    inverse_of: :releases
  has_one :announcement,
    class_name: "GamedbReleaseAnnouncement",
    foreign_key: :release_id,
    dependent: nil,
    inverse_of: :release

  # `format` is a NULL-or-{Physical,Digital} CHECK constraint in the DB (IGDB
  # imports leave it null). Validate it in the model so a bad value from the
  # release-create endpoint is a clean 422 instead of a CHECK violation 500.
  validates :format, inclusion: { in: %w[Physical Digital] }, allow_nil: true
end
