# frozen_string_literal: true

module Achievements
  # Opens a Sync Window (config/recurring.yml, 00/06/12/18 UTC, ADR 0003):
  # marks every Linked Account worth checking as due for an incremental sync,
  # then starts the three Provider ticks, which drain the marks and stop.
  #
  # Marked: backfilled accounts in `ok`, `pending` or `error` (transient) that
  # aren't already due; and, still as a Backfill, an `error` account whose
  # Backfill listing failed (else it would wait for Retry forever). Skipped: `private` / `not_found` (they wait for the
  # member's Retry), accounts still in their Backfill, departed members (their
  # data is kept, so a rejoin resumes without a new Backfill), and PSN accounts
  # while the club account's auth has expired (the PSN pause).
  #
  # A window that opens while the Achievement Hub is Off is skipped whole.
  class SyncWindowJob < ApplicationJob
    include CpuLogging

    MARKED_STATUSES = %w[ok pending error].freeze

    queue_as :default

    def perform
      return if Features.off?("achievement_hub")

      now = Time.current
      scope = eligible
      scope.where.not(backfilled_at: nil).update_all(sync_due_at: now, sync_mode: "incremental", updated_at: now)
      scope.where(backfilled_at: nil, sync_status: "error").update_all(sync_due_at: now, updated_at: now)
      ProviderTickJob.enqueue_all
    end

    private

    def eligible
      scope = UserLinkedAccount
        .where(sync_status: MARKED_STATUSES, sync_due_at: nil)
        .where(user_id: RpgClubUser.active.select(:user_id))
      psn_paused? ? scope.where.not(provider: "psn") : scope
    end

    # While PSN auth has expired, one auth attempt per window: a fixed NPSSO
    # (or a transient Sony failure) clears the pause on success, so PSN
    # resumes without anyone linking a new PSN account.
    def psn_paused?
      return false unless ProviderTickJob.paused?("psn")

      Providers.client_for("psn").authenticate!
      ProviderTickJob.paused?("psn")
    rescue Providers::Error => error
      Rails.logger.warn("[SyncWindow] PSN paused, auth still failing: #{error.message}")
      true
    end
  end
end
