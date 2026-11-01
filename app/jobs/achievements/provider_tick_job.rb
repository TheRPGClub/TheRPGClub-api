# frozen_string_literal: true

module Achievements
  # The engine that drains the durable sync state (ADR 0003). One chain per
  # Provider: each run performs one unit (the oldest set waiting for an import,
  # else the oldest account due for a listing) and, while anything is still
  # due, re-enqueues itself after the Provider's spacing. When nothing is due
  # the chain stops, so Neon can idle. The chain is also the global
  # per-Provider pacing: at most one call stream per Provider.
  class ProviderTickJob < ApplicationJob
    include CpuLogging

    # Seconds between two units of one Provider. PSN is one shared budget of
    # about 300 requests per 15 minutes across every member (research §4).
    SPACING = {
      "retroachievements" => 4.seconds,
      "steam" => 1.second,
      "psn" => 3.seconds
    }.freeze
    # Wait after a RateLimited that carried no Retry-After.
    RATE_LIMITED_WAIT = 60.seconds

    queue_as :default

    # One chain per Provider. A tick enqueued while that Provider's tick is
    # running (a window or boot catch-up landing mid-chain) is discarded, not
    # queued behind it: the running tick continues the chain, and a blocked
    # duplicate would run straight after it and start a second chain. The lock
    # outlasts a slow unit (a large Backfill listing).
    limits_concurrency to: 1, key: ->(provider) { provider.to_s }, on_conflict: :discard, duration: 15.minutes

    # The PSN pause: while the club account's auth has expired, no PSN unit
    # runs and the Sync Window marks no PSN account. The next successful PSN
    # auth (Psn::Client) clears `psn_auth_expired_at`.
    def self.paused?(provider)
      provider.to_s == "psn" && AchievementHubState.get(Psn::Client::AUTH_EXPIRED_KEY).present?
    end

    def perform(provider)
      provider = provider.to_s
      return if self.class.paused?(provider)

      run_one_unit(provider)
      self.class.set(wait: SPACING.fetch(provider)).perform_later(provider) if due?(provider)
    rescue Providers::RateLimited => error
      wait = error.retry_after.to_i.positive? ? error.retry_after.to_i.seconds : RATE_LIMITED_WAIT
      Rails.logger.warn("[ProviderTick] #{provider} rate limited; retrying in #{wait.to_i}s")
      self.class.set(wait: wait).perform_later(provider)
    rescue Providers::AuthExpired => error
      # The unit stays due; the chain resumes after the next successful auth.
      Rails.logger.warn("[ProviderTick] #{provider} auth expired; chain stopped: #{error.message}")
    rescue Providers::ConfigurationError => error
      # The deploy is missing the Provider's config; no account is at fault.
      Rails.logger.error("[ProviderTick] #{provider} is not configured; chain stopped: #{error.message}")
      raise
    end

    private

    def run_one_unit(provider)
      if (row = UserAchievementSetProgress.sync_pending(provider).first)
        SyncSet.call(row)
      elsif (account = UserLinkedAccount.sync_due(provider).first)
        ListAccount.call(account)
      end
    end

    def due?(provider)
      UserAchievementSetProgress.sync_pending(provider).exists? || UserLinkedAccount.sync_due(provider).exists?
    end
  end
end
