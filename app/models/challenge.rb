# frozen_string_literal: true

# A Challenge (GLOSSARY.md, "Challenges"; spec #376): a themed goal a member
# sets for the club, which other members take part in by starting a Run.
#
# Its Host is a member (`host_user_id`) or the club itself (null). Its
# schedule (Challenges::Schedule) is Always Open, until `ends_on` if set, or
# Seasonal, Open during a Season given as month and day that repeats every
# year. Whether it is Open or Closed is worked out from those dates in the
# club's time zone; the timed effects belong to the lifecycle job.
#
# Every Challenge has exactly one Challenge Format, and each Format keeps its
# own settings (Challenges::Formats): a Pool's definition is its sources
# (a linked Game List, Franchises and Series) plus its Core, Optional and excluded games, and a
# Run needs every Core Game and `pool_optional_target` Optional Games;
# a Slots range runs from `slots_first_year` (null: each member's birth year)
# to `slots_last_year` (null: the current year); an Assignment's Edition
# calendar is the sign-up cutoff, pick deadline and reveal date, each a month
# and day (`signup_cutoff_*`, `pick_deadline_*`, `reveal_*`), and it runs in
# yearly Editions, so it is Always Open with no end date.
#
# Its tint (Challenges::Tint) is the colour pair `tint_fill` / `tint_hi`: a
# curated one, chosen on create unless the request set one.
#
# Once the Challenge has any Run its rules are locked (RULE_ATTRIBUTES and
# the Format's locked settings, which for a Pool are none); its name,
# description and end date stay editable.
class Challenge < ApplicationRecord
  FORMATS = %w[slots pool assignment].freeze
  SCHEDULES = %w[always_open seasonal].freeze
  NAME_MAX = 100
  DESCRIPTION_MAX = 4000
  # The rule columns every Format shares; each Format adds its own
  # (Challenges::Formats::Pool#rules).
  RULE_ATTRIBUTES = %w[challenge_format schedule season_start_month season_start_day season_end_month
    season_end_day].freeze

  belongs_to :host, -> { without_images }, class_name: "RpgClubUser", foreign_key: :host_user_id, primary_key: :user_id, optional: true,
    inverse_of: false
  has_many :runs, class_name: "ChallengeRun", dependent: nil, inverse_of: :challenge
  has_many :pool_franchises, class_name: "ChallengePoolFranchise", dependent: nil, inverse_of: :challenge
  has_many :pool_collections, class_name: "ChallengePoolCollection", dependent: nil, inverse_of: :challenge
  has_many :pool_games, class_name: "ChallengePoolGame", dependent: nil, inverse_of: :challenge
  has_many :editions, class_name: "ChallengeEdition", dependent: nil, inverse_of: :challenge
  # The Game List a Pool was started from, a live source (Challenges::ListLink).
  belongs_to :pool_game_list, class_name: "GameList", optional: true, inverse_of: false
  # Rows go with the Challenge (the foreign key cascades).
  has_many :pool_list_notices, class_name: "ChallengePoolListNotice", dependent: nil, inverse_of: :challenge

  validates :name, presence: true, length: { maximum: NAME_MAX }
  validates :description, length: { maximum: DESCRIPTION_MAX }
  validates :challenge_format, inclusion: { in: FORMATS, message: "must be one of #{FORMATS.join(', ')}" }
  validates :schedule, inclusion: { in: SCHEDULES, message: "must be always_open or seasonal" }
  validates :pool_optional_target, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :schedule_fits

  before_create :assign_curated_tint, unless: :tint_fill?

  # Its dates decide when the lifecycle job next has work.
  after_commit { Challenges::SweepSchedule.clear }

  normalizes :name, with: ->(value) { value.squish }
  normalizes :description, with: ->(value) { value.strip }

  scope :visible, -> { where(hidden: false) }

  # The Challenges Open on `date` (the club's today by default), in SQL, so
  # lists can filter and page on it. Mirrors Challenges::Schedule#open_on?.
  scope :open_on, lambda { |date = Challenges.today|
    md = (date.month * 100) + date.day
    where(<<~SQL.squish, date: date, md: md)
      (schedule = 'always_open' AND (ends_on IS NULL OR ends_on >= :date))
      OR (schedule = 'seasonal' AND (
        (season_start_month * 100 + season_start_day <= season_end_month * 100 + season_end_day
          AND :md BETWEEN season_start_month * 100 + season_start_day AND season_end_month * 100 + season_end_day)
        OR (season_start_month * 100 + season_start_day > season_end_month * 100 + season_end_day
          AND (:md >= season_start_month * 100 + season_start_day OR :md <= season_end_month * 100 + season_end_day))))
    SQL
  }
  scope :closed_on, ->(date = Challenges.today) { where.not(id: open_on(date).select(:id)) }

  def club_hosted? = host_user_id.nil?

  def seasonal? = schedule == "seasonal"

  def always_open? = schedule == "always_open"

  def schedule_rules = Challenges::Schedule.for(self)

  def open?(date = Challenges.today) = schedule_rules.open_on?(date)

  def format_rules = Challenges::Formats.fetch(challenge_format)

  def runs? = runs.exists?

  def tint = Challenges::Tint::Pair.new(fill: tint_fill, hi: tint_hi)

  # Sets the tint, or with nil the Challenge's curated one (on create, once
  # it has an id).
  def tint=(pair)
    pair ||= (Challenges::Tint.fallback(self) if persisted?)
    self.tint_fill = pair&.fill
    self.tint_hi = pair&.hi
  end

  private

  # The curated tint turns by id, so the id is taken from its sequence first.
  def assign_curated_tint
    self.id ||= self.class.connection.select_value("SELECT nextval(pg_get_serial_sequence('challenges', 'id'))")
    self.tint = Challenges::Tint.fallback(self)
  end

  def schedule_fits
    return if errors.include?(:schedule)

    if seasonal?
      errors.add(:ends_on, "is only for Always Open Challenges") if ends_on
      Challenges::Schedule.season_errors(self).each { |message| errors.add(:season, message) }
    elsif [ season_start_month, season_start_day, season_end_month, season_end_day ].any?
      errors.add(:season, "is only for Seasonal Challenges")
    end
    assignment_schedule_fits if challenge_format == Challenges::Formats::Assignment::KEY
  end

  def assignment_schedule_fits
    errors.add(:base, "An Assignment Challenge runs in yearly Editions, so it is Always Open") if seasonal?
    errors.add(:base, "An Assignment Challenge runs in yearly Editions, so it has no end date") if ends_on
  end
end
