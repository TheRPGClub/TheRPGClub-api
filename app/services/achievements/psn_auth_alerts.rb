# frozen_string_literal: true

module Achievements
  # The staff alerts for the club PSN login (ticket #468), as bot jobs. They
  # go to a staff channel, so no Feature owns them.
  #
  # - `psn_auth_expired` { expired_at, reminder: false }: the login just
  #   expired (Psn::Client, once per expiry).
  # - `psn_auth_expired` { expired_at, reminder: true }: it is still expired
  #   (the Sync Window, at most once per REMIND_EVERY).
  # - `psn_auth_restored` { expired_at, restored_at }: a login worked again.
  module PsnAuthAlerts
    REMINDED_KEY = "psn_auth_reminded_at"
    REMIND_EVERY = 24.hours

    module_function

    def expired!(expired_at)
      BotJob.enqueue!(kind: "psn_auth_expired", summary: "PSN login expired; PSN sync paused",
        payload: { expired_at: expired_at, reminder: false })
    end

    def restored!(expired_at:, restored_at:)
      BotJob.enqueue!(kind: "psn_auth_restored", summary: "PSN login restored; PSN sync resumed",
        payload: { expired_at: expired_at, restored_at: restored_at })
    end

    # Queues a reminder when the login has been expired for REMIND_EVERY and
    # no reminder for this expiry went out within REMIND_EVERY. The reminder
    # time is kept on the hour, so the 6-hourly Sync Window reminds at the
    # same window every day instead of slipping a window when it runs a few
    # seconds early. Returns whether it queued one.
    def remind!(now: Time.current)
      expired_at = parse(AchievementHubState.get(Psn::Client::AUTH_EXPIRED_KEY))
      return false if expired_at.nil? || now - expired_at < REMIND_EVERY

      reminded_at = parse(AchievementHubState.get(REMINDED_KEY))
      return false if reminded_at && reminded_at > expired_at && now - reminded_at < REMIND_EVERY

      BotJob.enqueue!(kind: "psn_auth_expired", summary: "PSN login still expired (daily reminder)",
        payload: { expired_at: expired_at.iso8601, reminder: true })
      AchievementHubState.set(REMINDED_KEY, now.beginning_of_hour.iso8601)
      true
    end

    def parse(value)
      Time.iso8601(value.to_s) if value.present?
    rescue ArgumentError
      nil
    end
  end
end
