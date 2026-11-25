# frozen_string_literal: true

module Achievements
  # The Achievement Hub catch-up on boot (ADR 0003,
  # config/initializers/achievement_sync_catch_up.rb). The queue database is
  # recreated on every deploy, so the tick chains a deploy interrupted are
  # lost; their durable state in Postgres is not. This restarts them.
  #
  # While the PSN pause is on, it first tries one PSN login (ticket #468), so
  # a fresh PSN_NPSSO set with the deploy ends the pause by itself: success
  # clears `psn_auth_expired_at` (and queues the restored alert), and the PSN
  # tick enqueued after it runs. No Sony call is made while PSN auth is fine,
  # without an NPSSO, or while the Achievement Hub is Off (as in the Sync
  # Window). A failed login is logged and the ticks are enqueued anyway.
  class BootCatchUpJob < ApplicationJob
    queue_as :default

    def perform
      try_psn_login if ProviderTickJob.paused?("psn") && Psn::Client.npsso_configured? &&
        !Features.off?("achievement_hub")
      ProviderTickJob.enqueue_all
    end

    private

    def try_psn_login
      Providers.client_for("psn").authenticate!
      Rails.logger.info("[BootCatchUp] PSN login worked; PSN pause cleared")
    rescue StandardError => error
      Rails.logger.warn("[BootCatchUp] PSN paused, login still failing: #{error.class}: #{error.message}")
    end
  end
end
