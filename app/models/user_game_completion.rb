# frozen_string_literal: true

class UserGameCompletion < ApplicationRecord
  self.table_name = "user_game_completions"
  self.primary_key = "completion_id"

  # Run progress follows every commit (Challenges::CountsTowardRuns).
  include Challenges::CountsTowardRuns

  belongs_to :user,
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
  validate :started_not_after_finished, if: -> { started_at_changed? || completed_at_changed? }

  # The day the game was finished: the UTC date of `completed_at` (how the
  # export and the website read it). A new row without one takes the column
  # default, today.
  def finished_on
    return completed_at.utc.to_date if completed_at
    Time.current.utc.to_date if new_record?
  end

  private

  # A completion can't be finished after today, the club day.
  def finished_not_in_future
    return unless completed_at && ClubDay.after_today?(completed_at)

    errors.add(:completed_at, :finished_in_future, message: "can't be in the future")
  end

  def started_not_after_finished
    finished = finished_on
    return unless started_at && finished && started_at > finished

    errors.add(:started_at, :started_after_finished, message: "can't be after the day the game was finished")
  end
end
