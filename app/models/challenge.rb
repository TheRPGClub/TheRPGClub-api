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
# own settings (Challenges::Formats): a Pool's definition is the chosen
# franchises and collections plus games included or excluded by hand, and
# its target is `pool_target` Cleared games (null: every game in the Pool);
# a Slots range runs from `slots_first_year` (null: each member's birth year)
# to `slots_last_year` (null: the current year).
#
# Once the Challenge has any Run its rules are locked (RULE_ATTRIBUTES and
# the Format's settings); its name, description and end date stay editable.
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

  validates :name, presence: true, length: { maximum: NAME_MAX }
  validates :description, length: { maximum: DESCRIPTION_MAX }
  validates :challenge_format, inclusion: { in: FORMATS, message: "must be one of #{FORMATS.join(', ')}" }
  validates :schedule, inclusion: { in: SCHEDULES, message: "must be always_open or seasonal" }
  validates :pool_target, numericality: { only_integer: true, greater_than_or_equal_to: 1 }, allow_nil: true
  validate :schedule_fits

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

  # How many games a Pool Challenge's Pool holds now (the target "all").
  # Remembered on this record, which Runs loaded together share.
  def pool_game_count
    @pool_game_count ||= Challenges::PoolDefinition.of(self).games.count
  end

  private

  def schedule_fits
    return if errors.include?(:schedule)

    if seasonal?
      errors.add(:ends_on, "is only for Always Open Challenges") if ends_on
      Challenges::Schedule.season_errors(self).each { |message| errors.add(:season, message) }
    elsif [ season_start_month, season_start_day, season_end_month, season_end_day ].any?
      errors.add(:season, "is only for Seasonal Challenges")
    end
  end
end
