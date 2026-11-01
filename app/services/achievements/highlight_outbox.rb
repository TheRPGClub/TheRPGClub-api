# frozen_string_literal: true

module Achievements
  # The bot's view of the Achievement Hub: announceable Highlights the bot has
  # not announced yet, and the PSN auth alert. The bot acks each Unlock it
  # posts (`announced_at`), so each is posted once, whatever order the
  # concurrent Provider chains commit Unlocks in.
  module HighlightOutbox
    PSN_AUTH_EXPIRED_KEY = Psn::Client::AUTH_EXPIRED_KEY
    # The `psn_auth_expired_at` value the bot last posted. A new expiry
    # timestamp differs from it, which re-arms the alert.
    PSN_AUTH_ALERTED_KEY = "psn_auth_alerted_for"
    ALERTS = %w[psn_auth_expired].freeze
    LIMIT = 25
    MAX_ACK = 100

    module_function

    # Unannounced announceable Unlocks of active members, oldest first.
    def pending(limit: LIMIT)
      UserAchievementUnlock
        .where(announceable: true, announced_at: nil)
        .of_active_members
        .includes(:user, achievement: :achievement_set)
        .order(:id)
        .limit(limit)
    end

    # Stamps `announced_at` on the given announceable Unlocks. Idempotent: an
    # Unlock keeps its first time; ids that aren't announceable are ignored.
    # Returns the given ids that are now announced.
    def ack!(ids, now: Time.current)
      announceable = UserAchievementUnlock.where(id: ids, announceable: true)
      announceable.where(announced_at: nil).update_all(announced_at: now, updated_at: now)
      announceable.order(:id).ids
    end

    def alerts
      expired_at = AchievementHubState.get(PSN_AUTH_EXPIRED_KEY)
      {
        psn_auth_expired_at: expired_at,
        psn_auth_alerted: expired_at.present? && AchievementHubState.get(PSN_AUTH_ALERTED_KEY) == expired_at
      }
    end

    # Marks the current PSN auth expiry as posted. A no-op while PSN auth is
    # healthy.
    def ack_alert!(alert)
      raise ArgumentError, "unknown alert #{alert.inspect}" unless ALERTS.include?(alert)

      expired_at = AchievementHubState.get(PSN_AUTH_EXPIRED_KEY)
      AchievementHubState.set(PSN_AUTH_ALERTED_KEY, expired_at) if expired_at.present?
      alerts
    end
  end
end
