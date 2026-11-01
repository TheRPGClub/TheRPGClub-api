# frozen_string_literal: true

module Api
  module V1
    # The bot's Highlight endpoints (see Achievements::HighlightOutbox): list
    # announceable Unlocks past the cursor, ack the cursor, ack the PSN auth
    # alert. Service token only.
    class AchievementHighlightsController < ApplicationController
      before_action :require_service!

      # GET /api/v1/achievements/highlights/pending
      def pending
        unlocks = Achievements::HighlightOutbox.pending.to_a
        render json: {
          data: AchievementHighlightResource.new(unlocks).serializable_hash,
          meta: { cursor: Achievements::HighlightOutbox.cursor, next_cursor: unlocks.last&.id },
          alerts: Achievements::HighlightOutbox.alerts
        }
      end

      # POST /api/v1/achievements/highlights/ack { cursor }
      def ack
        cursor = Integer(params[:cursor].to_s, 10)
        raise ArgumentError if cursor.negative?

        render json: { data: { cursor: Achievements::HighlightOutbox.ack!(cursor) } }
      rescue ArgumentError
        render json: { error: "cursor must be a non-negative integer" }, status: :unprocessable_content
      end

      # POST /api/v1/achievements/alerts/ack { alert: "psn_auth_expired" }
      def ack_alert
        alert = params[:alert].to_s
        unless Achievements::HighlightOutbox::ALERTS.include?(alert)
          return render json: { error: "unknown alert" }, status: :unprocessable_content
        end

        render json: { data: Achievements::HighlightOutbox.ack_alert!(alert) }
      end
    end
  end
end
