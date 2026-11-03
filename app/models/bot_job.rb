# frozen_string_literal: true

# Work the API asks the bot to do in Discord (DM a giveaway key, post a
# Suggestion outcome, ...). The API cannot reach the bot, so the bot polls:
# it claims queued jobs, acts, then acks each one done or failed. A
# machine-local signal (BotJob::WorkSignal) lets that poll skip Postgres
# while nothing is waiting.
#
# Delivery is at-least-once: a claim not acked within LEASE goes back to
# queued, and after MAX_ATTEMPTS claims it fails instead.
#
# Enqueue with `BotJob.enqueue!(kind:, payload:, requested_by:)`. The
# payload is per kind; a breaking payload change gets a new kind name.
class BotJob < ApplicationRecord
  KINDS = %w[
    giveaway_claim_notice
    giveaway_hub_refresh
    suggestion_submitted
    suggestion_outcome
    voting_poll_wakeup
  ].freeze
  STATUSES = %w[queued claimed done failed].freeze
  LEASE = 5.minutes
  MAX_ATTEMPTS = 3
  TIMEOUT_ERROR = "Not acknowledged within the claim timeout"

  # Acking a job that already finished the other way.
  class AckConflict < StandardError; end

  belongs_to :requested_by, class_name: "RpgClubUser", foreign_key: :requested_by_user_id,
    primary_key: :user_id, optional: true, inverse_of: false

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :error_message, length: { maximum: 2000 }

  # Raised after commit, so a rolled-back enqueue (test mode, a failed
  # feature write) leaves the signal alone.
  after_commit(on: :create) { WorkSignal.set! }

  scope :queued, -> { where(status: "queued") }
  scope :claimed, -> { where(status: "claimed") }

  # The interface feature code uses. `requested_by` is the member whose
  # action caused the job (an RpgClubUser, a user id, or nil for system
  # jobs); they may read its status.
  def self.enqueue!(kind:, payload: {}, requested_by: nil)
    user_id = requested_by.is_a?(RpgClubUser) ? requested_by.user_id : requested_by&.to_s
    create!(kind: kind, payload: payload, requested_by_user_id: user_id)
  end

  # The bot's poll. While the signal is down this answers [] from SQLite
  # alone. Otherwise it returns expired claims to the queue, claims up to
  # `limit` queued jobs (oldest first; SKIP LOCKED lets overlapping polls
  # split the queue), and lowers the signal once nothing is queued, set to
  # come back up when the earliest open claim's lease runs out.
  def self.poll!(limit:, now: Time.current)
    signal = WorkSignal.read(now: now)
    return [] unless signal[:up]

    jobs = transaction do
      release_expired!(now)
      ids = queued.order(:id).limit(limit).lock("FOR UPDATE SKIP LOCKED").pluck(:id)
      where(id: ids).update_all([ "status = 'claimed', claimed_at = ?, attempts = attempts + 1, updated_at = ?", now, now ])
      where(id: ids).order(:id).to_a
    end

    unless queued.exists?
      WorkSignal.clear!(version: signal[:version], wake_at: claimed.minimum(:claimed_at)&.+(LEASE))
    end
    jobs
  end

  # Claims whose lease ran out: back to queued, or failed once they have
  # used every attempt.
  def self.release_expired!(now)
    expired = claimed.where(claimed_at: ..(now - LEASE))
    expired.where(attempts: MAX_ATTEMPTS..).update_all(
      status: "failed", error_message: TIMEOUT_ERROR, finished_at: now, updated_at: now
    )
    expired.update_all(status: "queued", claimed_at: nil, updated_at: now)
  end

  # Record the bot's outcome. Idempotent for a repeat of the same outcome; a
  # late ack of a job that went back to the queue still counts.
  def ack!(status:, error_message: nil, now: Time.current)
    with_lock do
      next if self.status == status
      raise AckConflict, "bot job #{id} is already #{self.status}" if %w[done failed].include?(self.status)

      update!(status: status, error_message: error_message, finished_at: now)
    end
    self
  end
end
