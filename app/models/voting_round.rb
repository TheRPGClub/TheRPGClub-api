# frozen_string_literal: true

# A GOTM / NR-GOTM round as the club runs it: nominations collect until
# `voting_opens_at`, members vote until `voting_closes_at`, then the tally
# decides the winners (an admin breaks ties) and the next round is scheduled.
# `round_number` is the round being nominated for, voted on and won.
#
# The phase is derived from the timestamps at read time, so what the API
# reports is right even when the Voting::AdvanceRounds sweep runs late; the
# sweep only performs the side effects (see Voting.automation_enabled?).
class VotingRound < ApplicationRecord
  self.primary_key = "round_number"

  PHASES = %w[nominating voting closed tie decided].freeze

  validates :round_number, :voting_opens_at, :voting_closes_at, :month_year, presence: true
  validate :closes_after_opens

  before_validation :apply_schedule_defaults

  scope :undecided, -> { where(decided_at: nil) }

  # The one round the club is on: the lowest one not yet decided.
  def self.current
    undecided.order(:round_number).first
  end

  # Whether member nominations for `round_number` are open. Only the current
  # round collects, and only until its vote opens.
  def self.nominations_open_for?(round_number, now = Time.current)
    current = self.current
    current.present? && current.round_number == round_number.to_i && current.nominations_open?(now)
  end

  # Whether voting on `round_number` is over. Rounds from before voting_rounds
  # existed have no row, and every round below the current one has finished.
  def self.ended?(round_number, now = Time.current)
    round = find_by(round_number: round_number.to_i)
    return round.voting_ended?(now) if round

    current = self.current
    current.present? && round_number.to_i < current.round_number
  end

  def phase(now = Time.current)
    return "decided" if decided_at.present?
    return "nominating" if now < voting_opens_at
    return "voting" if now < voting_closes_at
    return "tie" if pending_ties.present?

    "closed"
  end

  def nominations_open?(now = Time.current)
    phase(now) == "nominating"
  end

  def voting_open?(now = Time.current)
    phase(now) == "voting"
  end

  def voting_ended?(now = Time.current)
    %w[closed tie decided].include?(phase(now))
  end

  # Records the round as decided and schedules the next one. Idempotent; the
  # caller holds the row lock and has already recorded the winners.
  def decide!(now = Time.current)
    return if decided_at.present?

    update!(closed_at: closed_at || now, decided_at: now, pending_ties: {})
    self.class.create_or_find_by!(round_number: round_number + 1) do |following|
      following.voting_opens_at = Voting::Schedule.next_opens_at(voting_opens_at)
    end
  end

  private

  # Moving the open without an explicit close keeps the default weekend
  # window rather than leaving the old close behind (or before) it.
  def apply_schedule_defaults
    return if voting_opens_at.blank?

    self.voting_closes_at = Voting::Schedule.default_closes_at(voting_opens_at) if voting_closes_at.blank? ||
      (voting_opens_at_changed? && !voting_closes_at_changed? && persisted?)
    self.month_year = Voting::Schedule.month_label(voting_opens_at) if month_year.blank?
  end

  def closes_after_opens
    return if voting_opens_at.blank? || voting_closes_at.blank?
    return if voting_closes_at > voting_opens_at

    errors.add(:voting_closes_at, "must be after voting_opens_at")
  end
end
