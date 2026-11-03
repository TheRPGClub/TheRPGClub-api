# frozen_string_literal: true

# Work the API asks the bot to do in Discord (DM a giveaway key, post a
# Suggestion outcome, ...). The API cannot reach the bot, so the bot polls:
# it claims queued jobs, acts, then acks each one done or failed. A
# machine-local signal (BotJob::WorkSignal) lets that poll skip Postgres
# while nothing is waiting.
#
# Delivery is at-least-once: a claim not acked within its kind's lease
# (LEASES, else LEASE) goes back to queued, and after MAX_ATTEMPTS claims it
# fails instead.
#
# Enqueue with `BotJob.enqueue!(kind:, summary:, payload:, requested_by:)`.
# The summary is what the /admin activity list shows, so keep it plain and
# free of secrets (no game keys, tokens or other payload-only values). The
# payload is per kind and only the bot sees it; a breaking payload change
# gets a new kind name.
class BotJob < ApplicationRecord
  KINDS = %w[
    completion_announce
    giveaway_claim_notice
    giveaway_hub_refresh
    nomination_deleted
    suggestion_submitted
    suggestion_outcome
    voting_poll_wakeup
    voting_results_publish
    voting_panels_repost
    voting_tie_broken
    gotm_cache_reload
    presence_set
  ].freeze
  STATUSES = %w[queued claimed done failed].freeze
  # Default claim lease, and per-kind overrides for jobs the bot needs
  # longer to finish (e.g. a whole-guild scan).
  LEASE = 5.minutes
  LEASES = {}.freeze
  SUMMARY_MAX = 200
  TEXT_MAX = 2000
  MAX_ATTEMPTS = 3
  TIMEOUT_ERROR = "Not acknowledged within the claim timeout"

  # Acking a job that already finished the other way.
  class AckConflict < StandardError; end

  belongs_to :requested_by, class_name: "RpgClubUser", foreign_key: :requested_by_user_id,
    primary_key: :user_id, optional: true, inverse_of: false

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :summary, presence: true, length: { maximum: SUMMARY_MAX }
  validates :error_message, :result_text, length: { maximum: TEXT_MAX }

  # Raised after commit, so a rolled-back enqueue (test mode, a failed
  # feature write) leaves the signal alone.
  after_commit(on: :create) { WorkSignal.set! }

  scope :queued, -> { where(status: "queued") }
  scope :claimed, -> { where(status: "claimed") }

  # The interface feature code uses. `requested_by` is the member whose
  # action caused the job (an RpgClubUser, a user id, or nil for system
  # jobs); they may read its status. A long summary (a long title) is cut to
  # SUMMARY_MAX rather than failing the member's write.
  def self.enqueue!(kind:, summary:, payload: {}, requested_by: nil)
    user_id = requested_by.is_a?(RpgClubUser) ? requested_by.user_id : requested_by&.to_s
    create!(kind: kind, summary: summary.to_s.squish.truncate(SUMMARY_MAX), payload: payload,
      requested_by_user_id: user_id)
  end

  # How long a claim of `kind` may go unacked before it is handed out again.
  def self.lease_for(kind)
    LEASES.fetch(kind, LEASE)
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
      picked = queued.order(:id).limit(limit).lock("FOR UPDATE SKIP LOCKED").pluck(:id, :kind)
      picked.group_by { |_id, kind| lease_for(kind) }.each do |lease, rows|
        where(id: rows.map(&:first)).update_all([
          "status = 'claimed', claimed_at = ?, lease_expires_at = ?, attempts = attempts + 1, updated_at = ?",
          now, now + lease, now
        ])
      end
      where(id: picked.map(&:first)).order(:id).to_a
    end

    WorkSignal.clear!(version: signal[:version], wake_at: claimed.minimum(:lease_expires_at)) unless queued.exists?
    jobs
  end

  # Claims whose lease ran out: back to queued, or failed once they have
  # used every attempt.
  def self.release_expired!(now)
    expired = claimed.where(lease_expires_at: ..now)
    expired.where(attempts: MAX_ATTEMPTS..).update_all(
      status: "failed", error_message: TIMEOUT_ERROR, finished_at: now, updated_at: now
    )
    expired.update_all(status: "queued", claimed_at: nil, lease_expires_at: nil, updated_at: now)
  end

  # Record the bot's outcome: its error on failure, an optional result text
  # when done. Idempotent for a repeat of the same outcome (the first ack's
  # text stays); a late ack of a job that went back to the queue still counts.
  def ack!(status:, error_message: nil, result_text: nil, now: Time.current)
    with_lock do
      next if self.status == status
      raise AckConflict, "bot job #{id} is already #{self.status}" if %w[done failed].include?(self.status)

      update!(status: status, error_message: error_message, result_text: result_text, finished_at: now)
    end
    self
  end
end
