# frozen_string_literal: true

module Api
  module V1
    # Start a memberscan from the site (web parity 2, #337): the bot fetches
    # every guild member, upserts them and marks the rest departed, then acks
    # the `memberscan` job with its counts as the result text. Superadmin
    # only; the service token passes too.
    class MemberscanController < ApplicationController
      before_action :require_superadmin!

      SUMMARY = "Scan the server's members and update the member list"

      # POST /api/v1/memberscan. 202 with the queued BotJob.
      def create
        job = BotJob.enqueue!(kind: "memberscan", summary: SUMMARY, requested_by: requester_id)
        render json: { data: BotJobResource.new(job).serializable_hash }, status: :accepted
      end
    end
  end
end
