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
  include VoteWindows

  self.primary_key = "year"

  PHASES = %w[upcoming nominating voting closed runoff tie decided].freeze

  has_many :nominations, class_name: "GotyNomination", foreign_key: :year, primary_key: :year,
    dependent: nil, inverse_of: :goty_vote
  has_many :candidates, class_name: "GotyCandidate", foreign_key: :year, primary_key: :year,
    dependent: nil, inverse_of: :goty_vote
  has_many :ballot_votes, class_name: "GotyBallotVote", foreign_key: :year, primary_key: :year,
    dependent: nil, inverse_of: :goty_vote
  has_many :winners, class_name: "GotyWinner", foreign_key: :year, primary_key: :year,
    dependent: nil, inverse_of: :goty_vote

  validates :year, presence: true, numericality: { only_integer: true, greater_than: 1900 }
  validates :nominations_open_at, :voting_opens_at, :voting_closes_at, presence: true
  validate :dates_in_order

  before_validation :apply_schedule_defaults
  # The voting sweep (Goty::AdvanceVotes) schedules itself from the dates, so
  # a moved date or a step taken looks again on the next minute.
  after_commit { Voting::SweepSchedule.clear }

  # Year Y's GOTY Vote, created with the default schedule if it has none yet.
  # The lifecycle sweep calls it; safe to call twice.
  def self.ensure!(year)
    create_or_find_by!(year: year)
  end

  # Phases of an undecided GOTY Vote that is taking nominations or votes.
  OPEN_PHASES = %w[nominating voting runoff].freeze
  # Phases of one whose windows have run out, waiting on a tally or a tie.
  WAITING_PHASES = %w[closed tie].freeze
  # How long a decided GOTY Vote stays current, so its results stay up.
  DECIDED_CURRENT_FOR = 30.days

  # The Current GOTY Vote (GLOSSARY; spec api#481), the one members are
  # shown by default. The first of, in order:
  #   1. a GOTY Vote taking nominations or votes or in its runoff (the
  #      earliest year if several);
  #   2. one waiting on its tally or a tie (closed / tie; earliest year);
  #   3. one decided within the last 30 days (the latest decided_at);
  #   4. the upcoming one (earliest year).
  # So in January last year's is current while it runs, then for 30 days
  # after it is decided, while this year's waits upcoming; an old vote stuck
  # in a tie never hides a newer one that is open. nil when none applies.
  # The one place this rule lives: the website and the bot ask
  # GET /goty_votes/current.
  def self.current(now = Time.current)
    undecided = where(decided_at: nil).order(:year).to_a
    phases = undecided.index_with { |vote| vote.phase(now) }
    undecided.find { |vote| OPEN_PHASES.include?(phases[vote]) } ||
      undecided.find { |vote| WAITING_PHASES.include?(phases[vote]) } ||
      where(decided_at: (now - DECIDED_CURRENT_FOR)..now).order(decided_at: :desc, year: :desc).first ||
      undecided.find { |vote| phases[vote] == "upcoming" }
  end

  def nominations_open?(now = Time.current) = phase(now) == "nominating"

  private

  # Phases and runoff windows come from VoteWindows; before voting a GOTY
  # Vote is upcoming, then nominating.
  def phase_before_voting(now)
    return "upcoming" if now < nominations_open_at

    "nominating" if now < voting_opens_at
  end

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
