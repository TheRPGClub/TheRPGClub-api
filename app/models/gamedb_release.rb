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

  # How many months a vague Date Precision's period spans. A `day` is its own
  # one-day period; `tba` has none.
  PERIOD_MONTHS = { "month" => 1, "quarter" => 3, "year" => 12 }.freeze

  # Release Calendar placement (GLOSSARY "Release Calendar"): a quarter or
  # year is placed on the last day of its period, a month or day on its
  # stored date; on one day a month comes first (before day 1 of its month),
  # then the days, then a quarter, then a year. TBA goes after everything.
  PLACED_AT_PERIOD_END = %w[quarter year].freeze
  PLACEMENT_ORDER = %w[month day quarter year tba].freeze

  # The calendar period a date at a Date Precision covers, first..last day: the
  # day itself, or the whole month, quarter or year it starts. Nil for TBA.
  def self.period(date, date_precision)
    return nil if date.nil? || date_precision == "tba"

    months = PERIOD_MONTHS[date_precision]
    return date..date if months.nil?

    start = date.beginning_of_month.prev_month((date.month - 1) % months)
    start..(start.next_month(months) - 1)
  end

  # SQL for the last day of the period of the Release row `table` (an alias
  # with `release_date` and `date_precision`); NULL for TBA. The SQL twin of
  # ::period, so every "has this period ended" check agrees.
  def self.period_ends_on_sql(table)
    vague = PERIOD_MONTHS.map { |precision, months| "WHEN '#{precision}' THEN INTERVAL '#{months} months'" }.join(" ")
    "(#{table}.release_date + CASE #{table}.date_precision #{vague} ELSE INTERVAL '1 day' END - INTERVAL '1 day')::date"
  end

  # Ranks a Date Precision from most to least precise (DATE_PRECISIONS
  # order: day first, TBA last), for "the more precise one wins a tie".
  def self.precision_rank(date_precision)
    DATE_PRECISIONS.index(date_precision)
  end

  # This Release's period (::period); nil for TBA.
  def period
    self.class.period(release_date, date_precision)
  end

  # The day the Release Calendar places this Release on; nil for TBA.
  def placed_on
    date_precision.in?(PLACED_AT_PERIOD_END) ? period.end : release_date
  end

  # Sorts Releases in Release Calendar placement order, TBA last.
  def placement_key
    [ placed_on ? 0 : 1, placed_on || Date.new(0), PLACEMENT_ORDER.index(date_precision) || PLACEMENT_ORDER.size ]
  end

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
    return if release_date == period.begin

    errors.add(:release_date, "must be the first day of its #{date_precision}")
  end
end
