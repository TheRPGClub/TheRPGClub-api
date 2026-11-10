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
# gets a new kind name. A kind that posts publicly is owned by a Feature
# (PUBLIC_POST_FEATURES), and its payload carries that Feature's key as
# `feature_key`, so the bot can route the post by its Feature Flag. A kind
# that does a Feature's work without posting can carry its key the same way
# (FEATURE_WORK).
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
    live_event_create
    say
    memberscan
    presence_set
    feature_flag_changed
    news_images_renew
    news_catch_up
  ].freeze
  # The kinds that post, and the Feature each post belongs to (the posts in
  # Features::REGISTRY's coverage): the claim notice's claim log and the
  # submitted Suggestion's announcement included. The other kinds post to a
  # staff channel or post nothing.
  PUBLIC_POST_FEATURES = {
    "completion_announce" => "game_completions",
    "giveaway_claim_notice" => "giveaways",
    "giveaway_hub_refresh" => "giveaways",
    "nomination_deleted" => "voting_gotm",
    "suggestion_submitted" => "suggestions",
    "suggestion_outcome" => "suggestions",
    "voting_results_publish" => "voting_gotm",
    "voting_panels_repost" => "voting_gotm",
    "voting_tie_broken" => "voting_gotm"
  }.freeze
  # Kinds that post nothing but do a Feature's work, and that Feature: the
  # News Hub's image renewal and catch-up scan (ticket #358).
  FEATURE_WORK = {
    "news_images_renew" => "news_hub",
    "news_catch_up" => "news_hub"
  }.freeze
  FEATURE_KEYS = PUBLIC_POST_FEATURES.merge(FEATURE_WORK).freeze
  STATUSES = %w[queued claimed done failed].freeze
  # Default claim lease, and per-kind overrides for jobs the bot needs
  # longer to finish (e.g. a whole-guild scan).
  LEASE = 5.minutes
  LEASES = {
    "memberscan" => 30.minutes,
    "news_catch_up" => 30.minutes
  }.freeze
  SUMMARY_MAX = 200
  TEXT_MAX = 2000
  MAX_ATTEMPTS = 3
  TIMEOUT_ERROR = "Not acknowledged within the claim timeout"
  # A claim's lease expiry. The previous release claims without one (only
  # claimed_at), so during a deploy such a claim gets the default lease.
  LEASE_EXPIRY_SQL = "COALESCE(lease_expires_at, claimed_at + interval '#{LEASE.to_i} seconds')".freeze

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
    create!(kind: kind, summary: summary.to_s.squish.truncate(SUMMARY_MAX), payload: with_feature_key(kind, payload),
      requested_by_user_id: user_id)
  end

  # Queues one job of `kind` per entry of `jobs` (each { summary:, payload: })
  # in one statement, leaving out every one a partial unique index on open
  # jobs of that kind already covers (ux_bot_jobs_one_open_news_images_renew
  # allows one open news_images_renew per message), so racing requests queue
  # it once. System jobs: no requester. Returns how many were queued.
  def self.enqueue_once!(kind:, jobs:)
    return 0 if jobs.empty?

    now = Time.current
    rows = jobs.map do |job|
      { kind: kind, summary: job.fetch(:summary).to_s.squish.truncate(SUMMARY_MAX),
        payload: with_feature_key(kind, job.fetch(:payload)), created_at: now, updated_at: now }
    end
    # No conflict target: ON CONFLICT DO NOTHING skips a row any unique index rejects.
    queued = insert_all(rows, returning: %i[id]).length
    # insert_all runs no callbacks, so raise the signal here.
    WorkSignal.set! if queued.positive?
    queued
  end

  def self.with_feature_key(kind, payload)
    feature_key = FEATURE_KEYS[kind.to_s]
    feature_key ? payload.to_h.stringify_keys.merge("feature_key" => feature_key) : payload
  end
  private_class_method :with_feature_key

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

    WorkSignal.clear!(version: signal[:version], wake_at: earliest_lease_expiry) unless queued.exists?
    jobs
  end

  # When the earliest open claim's lease runs out (nil without one).
  def self.earliest_lease_expiry
    claimed.pick(Arel.sql("MIN(#{LEASE_EXPIRY_SQL})"))
  end

  # Claims whose lease ran out: back to queued, or failed once they have
  # used every attempt.
  def self.release_expired!(now)
    expired = claimed.where("#{LEASE_EXPIRY_SQL} <= ?", now)
    exhausted = expired.where(attempts: MAX_ATTEMPTS..).pluck(:id, :kind)
    if exhausted.any?
      where(id: exhausted.map(&:first)).update_all(
        status: "failed", error_message: TIMEOUT_ERROR, finished_at: now, updated_at: now
      )
      jobs_failed!(exhausted, now)
    end
    expired.update_all(status: "queued", claimed_at: nil, lease_expires_at: nil, updated_at: now)
  end

  # What a kind's record does when its job ends failed (acked failed, or out
  # of attempts). `rows` are [id, kind] pairs.
  def self.jobs_failed!(rows, now)
    live_event_jobs = rows.filter_map { |id, kind| id if kind == "live_event_create" }
    LiveEvent.bot_jobs_failed!(live_event_jobs, now: now) if live_event_jobs.any?
  end

  # Record the bot's outcome: its error on failure, an optional result text
  # when done (either cut to TEXT_MAX, so a long text never fails the ack and
  # reruns the job). Idempotent for a repeat of the same outcome (the first ack's
  # text stays); a late ack of a job that went back to the queue still counts.
  def ack!(status:, error_message: nil, result_text: nil, now: Time.current)
    with_lock do
      next if self.status == status
      raise AckConflict, "bot job #{id} is already #{self.status}" if %w[done failed].include?(self.status)

      update!(status: status, error_message: error_message&.truncate(TEXT_MAX),
        result_text: result_text&.truncate(TEXT_MAX), finished_at: now)
      self.class.jobs_failed!([ [ id, kind ] ], now) if status == "failed"
    end
    self
  end
end
