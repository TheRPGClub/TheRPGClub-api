# frozen_string_literal: true

# The outbox of Discord posts a round's phase changes call for. The backend
# cannot reach the bot, so the bot polls: it claims due events (a lease),
# posts, then acks. Delivery is at-least-once; the lease keeps a restarting
# bot from double-posting and `expires_at` keeps a backlog from posting stale
# messages (a nomination reminder after voting opened, say).
class VotingEvent < ApplicationRecord
  KINDS = %w[
    nomination_reminder_5d nomination_reminder_1d
    voting_opened voting_closed
    runoff_opened runoff_closed
    tie_pending round_decided
  ].freeze
  LEASE = 5.minutes
  # How long after an event falls due the every-minute sweep
  # (Voting::AdvanceRoundsJob) has queued it: a minute, plus Solid Queue's
  # dispatch and pickup polling (config/queue.yml).
  SWEEP_LAG = 90.seconds

  validates :round_number, :kind, :available_at, presence: true

  # The sweep skips kinds already queued, so a queued or removed event changes
  # when it next has work. Not on update: claims and acks do not.
  after_commit(on: %i[create destroy]) { Voting::SweepSchedule.clear }
  validates :kind, inclusion: { in: KINDS }

  scope :claimable, lambda { |now|
    where(delivered_at: nil)
      .where(available_at: ..now)
      .where("expires_at IS NULL OR expires_at > ?", now)
      .where("claimed_until IS NULL OR claimed_until <= ?", now)
  }

  # Queues `kind` for the round once; later calls are no-ops (the unique
  # round/kind index is the backstop). Does nothing while the backend is not
  # running the lifecycle itself.
  def self.emit!(round_number:, kind:, available_at: Time.current, expires_at: nil, payload: {})
    return unless Voting.automation_enabled?

    create_or_find_by!(round_number: round_number, kind: kind) do |event|
      event.available_at = available_at
      event.expires_at = expires_at
      event.payload = payload
    end
  end

  # Leases up to `limit` due events to the caller, oldest first. SKIP LOCKED
  # lets two concurrent claims split the queue instead of sharing events.
  def self.claim!(limit:, now: Time.current)
    transaction do
      ids = claimable(now).order(:available_at, :id).limit(limit).lock("FOR UPDATE SKIP LOCKED").pluck(:id)
      where(id: ids).update_all([ "claimed_until = ?, attempts = attempts + 1, updated_at = ?", now + LEASE, now ])
      where(id: ids).order(:available_at, :id).to_a
    end
  end

  # When the bot should claim next: now while an event is claimable,
  # otherwise when the earliest pending one falls due or its lease runs out,
  # or once the sweep has queued the round's next event. nil when nothing is
  # pending or scheduled. The bot sleeps until then, so a quiet outbox lets
  # Neon's compute suspend instead of a fixed poll keeping it awake.
  def self.next_poll_at(now = Time.current)
    pending = where(delivered_at: nil)
      .where("expires_at IS NULL OR expires_at > ?", now)
      .pluck(:available_at, :claimed_until)
      .map { |available_at, claimed_until| [ available_at, claimed_until ].compact.max }
    swept = Voting::AdvanceRounds.next_event_at(now: now)&.+(SWEEP_LAG)
    soonest = [ *pending, swept ].compact.min
    [ soonest, now ].max if soonest
  end

  def acknowledge!(now = Time.current)
    update!(delivered_at: now) if delivered_at.nil?
  end
end
