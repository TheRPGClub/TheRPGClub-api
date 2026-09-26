# frozen_string_literal: true

module Api
  module V1
    # The bot's outbox (see VotingEvent): claim due events, post them to
    # Discord, ack each one. Service token only.
    class VotingEventsController < ApplicationController
      before_action :require_service!

      DEFAULT_CLAIM = 10
      MAX_CLAIM = 50

      # POST /api/v1/voting_events/claim?limit=N — leases up to N due events.
      def claim
        limit = params[:limit].present? ? params[:limit].to_i.clamp(1, MAX_CLAIM) : DEFAULT_CLAIM
        render json: { data: VotingEventResource.new(VotingEvent.claim!(limit: limit)).serializable_hash }
      end

      # POST /api/v1/voting_events/:id/ack — idempotent.
      def ack
        event = VotingEvent.find(params[:id])
        event.acknowledge!
        render json: { data: VotingEventResource.new(event).serializable_hash }
      end
    end
  end
end
