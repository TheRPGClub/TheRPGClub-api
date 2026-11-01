# frozen_string_literal: true

module Achievements
  # What the two sync units (ListAccount, SyncSet) share: how a Provider
  # failure lands in the durable sync state (ADR 0003), and how a Linked
  # Account is finished once none of its sets is waiting for an import.
  module SyncUnit
    # Re-raised by both units, leaving the state untouched: AuthExpired and
    # RateLimited so a later tick retries (the tick owns back-off), and a
    # missing Provider configuration, which is the deploy's fault, not the
    # account's.
    PASSED_THROUGH = [ Providers::AuthExpired, Providers::RateLimited, Providers::ConfigurationError ].freeze

    private

    # For account-level calls (the listing). Private / NotFound stop the
    # account's syncing until the member presses Retry. Anything else marks
    # the account errored (transient: the next Sync Window or Sync now lists it
    # again) and clears only this unit's marker, so one bad unit can't wedge
    # the queue.
    def with_sync_errors(account)
      yield
    rescue *PASSED_THROUGH
      raise
    rescue Providers::Private, Providers::NotFound => error
      stop_account(account, error.is_a?(Providers::Private) ? "private" : "not_found", error.message)
      nil
    rescue StandardError => error
      account.update!(sync_status: "error", sync_error: error.message)
      clear_unit_marker
      nil
    end

    def stop_account(account, status, message)
      UserLinkedAccount.transaction do
        account.update!(sync_status: status, sync_error: message, sync_due_at: nil)
        account.set_progress.where.not(sync_pending_at: nil).update_all(sync_pending_at: nil)
      end
    end

    # Once no set of the account waits for an import: stamps last_synced_at
    # with `cursor` (the time of the listing that queued the sets, so activity
    # during a long import is caught by the next incremental listing), and
    # backfilled_at after a Backfill; then the account is ok and incremental.
    # An `error` account (a failed earlier listing) finishes too; only a
    # stopped (private / not_found) one waits for Retry.
    def finish_if_drained(account, cursor:, now:)
      return if account.set_progress.where.not(sync_pending_at: nil).exists?

      account.reload
      return if account.sync_private? || account.sync_not_found?

      account.update!(
        last_synced_at: cursor,
        backfilled_at: account.backfill? ? now : account.backfilled_at,
        sync_status: "ok",
        sync_error: nil,
        sync_mode: "incremental"
      )
    end
  end
end
