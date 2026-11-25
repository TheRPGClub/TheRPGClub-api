# frozen_string_literal: true

# A Playthrough (GLOSSARY.md, spec api#457): one run of a game by a member.
# Its time is the total the member set by hand (`manual_total_minutes`), or
# else the Playtime gained since it started: the member's Playtime now minus
# `baseline_minutes`, floored at 0. Manual Playtime added while it's open
# raises Playtime, so it counts without extra work.
#
# Open while `ended_at` is null, and at most one open per member and game.
# It ends `completed` (a Game Completion closed it) or `abandoned`;
# `final_minutes` keeps its time from that moment.
class UserGamePlaythrough < ApplicationRecord
  END_REASONS = %w[completed abandoned].freeze

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    inverse_of: false
  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    primary_key: :game_id,
    inverse_of: false
  belongs_to :completion,
    class_name: "UserGameCompletion",
    foreign_key: :completion_id,
    primary_key: :completion_id,
    optional: true,
    inverse_of: false

  enum :end_reason, END_REASONS.index_with(&:itself), validate: { allow_nil: true }

  validates :baseline_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :manual_total_minutes, :final_minutes,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :currently_open, -> { where(ended_at: nil) }
  scope :ended, -> { where.not(ended_at: nil) }

  def open? = ended_at.nil?

  def manual? = !manual_total_minutes.nil?

  # Its time, given the member's Playtime for the game now. An ended one
  # keeps the time it closed with.
  def minutes_at(playtime_minutes)
    return final_minutes unless open?
    return manual_total_minutes if manual?

    [ playtime_minutes - baseline_minutes, 0 ].max
  end
end
