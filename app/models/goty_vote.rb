# frozen_string_literal: true

# A year's GOTY Vote (GLOSSARY "GOTY Vote"; spec api#471), keyed by the year
# it decides. Game of the Year nominations run from `nominations_open_at`
# until `voting_opens_at`, when all three Awards open for voting until
# `voting_closes_at`. Awards the vote leaves tied share one runoff
# (`runoff_opens_at` .. `runoff_closes_at`); one that ties again waits in
# `pending_ties` for an admin. `runoff_ties` keeps the runoff's ballot.
#
# As for VotingRound, the phase is derived from the timestamps at read time;
# the lifecycle sweep only performs the side effects. Between a window
# closing and the sweep's tally the phase reads `closed`.
class GotyVote < ApplicationRecord
  self.primary_key = "year"

  PHASES = %w[upcoming nominating voting closed runoff tie decided].freeze

  validates :year, presence: true, numericality: { only_integer: true, greater_than: 1900 }
  validates :nominations_open_at, :voting_opens_at, :voting_closes_at, presence: true
  validate :dates_in_order

  before_validation :apply_schedule_defaults

  # Year Y's GOTY Vote, created with the default schedule if it has none yet.
  # The lifecycle sweep calls it; safe to call twice.
  def self.ensure!(year)
    create_or_find_by!(year: year)
  end

  def phase(now = Time.current)
    return "decided" if decided_at.present?
    return "upcoming" if now < nominations_open_at
    return "nominating" if now < voting_opens_at
    return "voting" if now < voting_closes_at
    if runoff_closes_at.present?
      return "runoff" if now < runoff_closes_at
      return "closed" if runoff_closed_at.nil?
    end
    return "tie" if pending_ties.present?

    "closed"
  end

  def nominations_open?(now = Time.current) = phase(now) == "nominating"

  def voting_open?(now = Time.current) = phase(now) == "voting"

  def runoff_open?(now = Time.current) = phase(now) == "runoff"

  private

  # Missing dates take the default schedule. Moving the voting open without
  # an explicit close keeps the default weekend window, as for VotingRound.
  def apply_schedule_defaults
    return if year.blank?

    self.nominations_open_at ||= Goty::Schedule.nominations_open_at(year)
    self.voting_opens_at ||= Goty::Schedule.voting_opens_at(year)
    return if voting_opens_at.blank?

    self.voting_closes_at = Goty::Schedule.voting_closes_at(voting_opens_at) if voting_closes_at.blank? ||
      (voting_opens_at_changed? && !voting_closes_at_changed? && persisted?)
  end

  def dates_in_order
    return if nominations_open_at.blank? || voting_opens_at.blank? || voting_closes_at.blank?

    errors.add(:voting_opens_at, "must be after nominations_open_at") unless voting_opens_at > nominations_open_at
    errors.add(:voting_closes_at, "must be after voting_opens_at") unless voting_closes_at > voting_opens_at
    return if runoff_opens_at.blank? || runoff_closes_at.blank? || runoff_closes_at > runoff_opens_at

    errors.add(:runoff_closes_at, "must be after runoff_opens_at")
  end
end
