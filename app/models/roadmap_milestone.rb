# frozen_string_literal: true

# A Milestone on the Roadmap (GLOSSARY.md "Milestone", "Reached"; spec
# api#505): a named stop in the order staff choose, with an optional blurb
# and a target date known to a Date Precision (TBA, with no date, by default).
#
# All Milestones share one `position` order, Reached or not: a Reached one
# keeps its place, so taking it back from Reached returns it there. A
# Milestone with Roadmap Items can't be deleted (the foreign key refuses it).
class RoadmapMilestone < ApplicationRecord
  NAME_MAX = 100
  BLURB_MAX = 280
  # The Release Date Precisions (GamedbRelease::DATE_PRECISIONS).
  DATE_PRECISIONS = GamedbRelease::DATE_PRECISIONS

  has_many :items, -> { order(:position, :id) },
    class_name: "RoadmapItem",
    foreign_key: :milestone_id,
    inverse_of: :milestone,
    dependent: :restrict_with_error

  # Open Milestones in staff order; Reached ones newest Reached first.
  scope :open, -> { where(reached_at: nil).order(:position, :id) }
  scope :reached, -> { where.not(reached_at: nil).order(reached_at: :desc, id: :desc) }

  normalizes :name, with: ->(value) { value.strip }
  normalizes :blurb, with: ->(value) { value.strip.presence }

  validates :name, presence: true, length: { maximum: NAME_MAX }
  validates :blurb, length: { maximum: BLURB_MAX }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :date_precision, inclusion: { in: DATE_PRECISIONS, message: "must be one of #{DATE_PRECISIONS.join(', ')}" }
  validate :target_date_matches_precision

  # A vague target date is kept on the first day of its period, whatever day
  # inside it was sent, as a Release's is.
  before_validation do
    next if target_date.nil? || !date_precision.in?(DATE_PRECISIONS - %w[tba])

    self.target_date = GamedbRelease.period(target_date, date_precision).begin
  end

  def reached? = reached_at.present?

  private

  # Mirrors the DB's TBA CHECK: only TBA has no date.
  def target_date_matches_precision
    return unless date_precision.in?(DATE_PRECISIONS)

    if date_precision == "tba"
      errors.add(:target_date, "must be empty for TBA") if target_date
    elsif target_date.nil?
      errors.add(:target_date, "is required unless the Milestone is TBA")
    end
  end
end
