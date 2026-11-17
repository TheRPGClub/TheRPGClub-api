# frozen_string_literal: true

class GamedbRelease < ApplicationRecord
  self.table_name = "gamedb_releases"
  self.primary_key = "release_id"

  # Where a Release comes from (ADR 0009). An IGDB Release is kept in step by
  # the in-place IGDB refresh (Gamedb::ReleaseSync): its date can move and it
  # can be removed. A Manual Release (staff, the Completionator import, any
  # other writer) is never changed or removed by a refresh, only adopted when
  # IGDB reports the same game, platform and region.
  SOURCES = %w[igdb manual].freeze

  enum :source, SOURCES.index_with(&:itself), prefix: true, validate: true

  # How exactly a Release's date is known (api#392). `release_date` is a plain
  # calendar date stored at that precision: the day itself, the first day of
  # its month or quarter, 1 January of its year, or no date at all for `tba`.
  # Only `day` Releases are announced.
  DATE_PRECISIONS = %w[day month quarter year tba].freeze

  enum :date_precision, DATE_PRECISIONS.index_with(&:itself), prefix: true, validate: true

  # A Release with no date is TBA, whoever wrote it (a Manual Release from POST
  # /games/:id/releases or an import that knows no date).
  before_validation { self.date_precision = "tba" if release_date.nil? }

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
  validate :release_date_matches_precision

  private

  # Mirrors the DB's TBA CHECK, and keeps a vague date on the first day of its
  # period so the Release Calendar can place it.
  def release_date_matches_precision
    return if release_date.nil? || !date_precision.in?(DATE_PRECISIONS)
    return errors.add(:release_date, "must be empty for a TBA Release") if date_precision_tba?
    return if release_date == period_start

    errors.add(:release_date, "must be the first day of its #{date_precision}")
  end

  def period_start
    case date_precision
    when "month" then release_date.beginning_of_month
    when "quarter" then release_date.beginning_of_quarter
    when "year" then release_date.beginning_of_year
    else release_date
    end
  end
end
