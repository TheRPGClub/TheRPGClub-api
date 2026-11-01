# frozen_string_literal: true

module Api
  module V1
    # The bot's Highlight endpoints (see Achievements::HighlightOutbox): list
    # unannounced Highlights, ack the posted ones, ack the PSN auth alert.
    # Service token only.
    class AchievementHighlightsController < ApplicationController
      before_action :require_service!

      # GET /api/v1/achievements/highlights/pending
      def pending
        unlocks = Achievements::HighlightOutbox.pending.to_a
        render json: {
          data: AchievementHighlightResource.new(unlocks).serializable_hash,
          alerts: Achievements::HighlightOutbox.alerts
        }
      end

      # POST /api/v1/achievements/highlights/ack { data: { ids: [..] } }
      def ack
        ids = ack_ids
        unless ids
          return render json: {
            error: "data.ids must be an array of at most #{Achievements::HighlightOutbox::MAX_ACK} positive integers"
          }, status: :unprocessable_content
        end

        render json: { data: { ids: Achievements::HighlightOutbox.ack!(ids) } }
      end

      # POST /api/v1/achievements/alerts/ack { alert: "psn_auth_expired" }
      def ack_alert
        alert = params[:alert].to_s
        unless Achievements::HighlightOutbox::ALERTS.include?(alert)
          return render json: { error: "unknown alert" }, status: :unprocessable_content
        end

        render json: { data: Achievements::HighlightOutbox.ack_alert!(alert) }
      end

      private

      # The posted Unlock ids, or nil when malformed.
      def ack_ids
        ids = params.dig(:data, :ids)
        return unless ids.is_a?(Array) && ids.size <= Achievements::HighlightOutbox::MAX_ACK

        ids = ids.map { |id| id.is_a?(Integer) || id.is_a?(String) ? Integer(id.to_s, 10, exception: false) : nil }
        ids if ids.all? { |id| id&.positive? }
      end
    end
  end
end
