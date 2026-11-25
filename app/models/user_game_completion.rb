# frozen_string_literal: true

class UserGameCompletion < ApplicationRecord
  self.table_name = "user_game_completions"
  self.primary_key = "completion_id"

  # Run progress follows every commit (Challenges::CountsTowardRuns).
  include Challenges::CountsTowardRuns

  belongs_to :user, -> { without_images },
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    optional: true,
    inverse_of: :game_completions
  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    inverse_of: :user_game_completions
  belongs_to :platform,
    class_name: "GamedbPlatform",
    foreign_key: :platform_id,
    optional: true,
    inverse_of: :user_game_completions

  validates :user_id, :gamedb_game_id, :completion_type, presence: true
  # Checked only when a date is set or changed, so rows saved before the
  # checks existed still take other edits.
  validate :finished_not_in_future, if: :completed_at_changed?
  validate :started_not_in_future, if: -> { started_at_changed? || completed_at_changed? }

  # A completion logged without a Finished day was finished today. An explicit
  # `completed_at: nil` stays nil (an unknown day).
  before_validation :finish_today, on: :create, unless: -> { @completed_at_given }

  # `completed_at` is a day (spec api#451, the day rule): whatever a writer
  # sends (the website's `YYYY-MM-DD`, the bot's "now", an import's Date) is
  # stored as noon club time of the club day it names (ClubDay.day_named).
  # An unreadable value is left to the usual cast (nil).
  def completed_at=(value)
    @completed_at_given = true
    day = ClubDay.day_named(value)
    super(day ? ClubDay.noon(day) : value)
    # Force a nil into the INSERT; otherwise the column default (today) wins.
    completed_at_will_change! if new_record? && completed_at.nil?
  end

  # `started_at` is a date column with the same day semantics: a full
  # timestamp names its club day, not its UTC date.
  def started_at=(value)
    super(ClubDay.day_named(value) || value)
  end

  # The day the game was finished (ClubDay.day_of), nil when unknown.
  def finished_on = ClubDay.day_of(completed_at)

  private

  def finish_today
    self.completed_at = ClubDay.noon(ClubDay.today)
  end

  # A completion can't be finished after today, the club day.
  def finished_not_in_future
    return unless completed_at && finished_on > ClubDay.today

    errors.add(:completed_at, :finished_in_future, message: "can't be in the future")
  end

  # Started can't be after Finished, nor after today when there's no Finished.
  def started_not_in_future
    return unless started_at

    finished = finished_on
    if finished && started_at > finished
      errors.add(:started_at, :started_after_finished, message: "can't be after the day the game was finished")
    elsif finished.nil? && started_at > ClubDay.today
      errors.add(:started_at, :started_in_future, message: "can't be in the future")
    end
  end
end
