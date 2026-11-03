# frozen_string_literal: true

module Api
  module V1
    # Make the bot say something (web parity 2, #337; see BotSay).
    # Superadmin only; the service token passes too.
    class BotSayController < ApplicationController
      before_action :require_superadmin!

      # POST /api/v1/bot_say
      # Body: { "data": { "channel_id", "content", "reply_to_message_link"? } }
      # 202 with the queued BotJob; 422 for a channel that is not a synced
      # text channel, blank or too long content, or a bad message link.
      def create
        data = params.fetch(:data, {})
        job = BotSay.enqueue!(
          channel_id: data[:channel_id], content: data[:content],
          reply_to_message_link: data[:reply_to_message_link],
          requested_by: requester_id
        )
        render json: { data: BotJobResource.new(job).serializable_hash }, status: :accepted
      rescue BotSay::Invalid => e
        render json: { error: e.message }, status: :unprocessable_content
      end
    end
  end
end
