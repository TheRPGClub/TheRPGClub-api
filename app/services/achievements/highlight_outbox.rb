# frozen_string_literal: true

module Achievements
  # The bot's view of the Achievement Hub: announceable Highlights past a
  # stored cursor, and the PSN auth alert. The cursor is the id of the last
  # Unlock the bot posted, kept in AchievementHubState; it only moves forward,
  # so the bot can't double-post across restarts.
  module HighlightOutbox
    CURSOR_KEY = "bot_highlight_cursor"
    PSN_AUTH_EXPIRED_KEY = "psn_auth_expired_at"
    # The `psn_auth_expired_at` value the bot last posted. A new expiry
    # timestamp differs from it, which re-arms the alert.
    PSN_AUTH_ALERTED_KEY = "psn_auth_alerted_for"
    ALERTS = %w[psn_auth_expired].freeze
    LIMIT = 25

    module_function

    def cursor
      AchievementHubState.get(CURSOR_KEY).to_i
    end

    # Announceable Unlocks of active members past the cursor, oldest first.
    def pending(limit: LIMIT)
      UserAchievementUnlock
        .where(announceable: true)
        .where(UserAchievementUnlock.arel_table[:id].gt(cursor))
        .of_active_members
        .includes(:user, achievement: :achievement_set)
        .order(:id)
        .limit(limit)
    end

    # Moves the cursor to `value` unless it is already further along (a stale
    # ack is a no-op). Atomic, so concurrent acks can't move it backwards.
    # Returns the stored cursor.
    def ack!(value)
      sql = <<~SQL.squish
        INSERT INTO achievement_hub_states (key, value, created_at, updated_at)
        VALUES (:key, to_jsonb(:value::bigint), now(), now())
        ON CONFLICT (key) DO UPDATE
          SET value = to_jsonb(GREATEST((achievement_hub_states.value #>> '{}')::bigint, :value::bigint)),
              updated_at = now()
        RETURNING (value #>> '{}')::bigint
      SQL
      AchievementHubState.connection.select_value(
        AchievementHubState.sanitize_sql([ sql, { key: CURSOR_KEY, value: value } ])
      ).to_i
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
