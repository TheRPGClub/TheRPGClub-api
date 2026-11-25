# frozen_string_literal: true

module Api
  module V1
    # Franchise Progress (spec api#457, ticket api#461; Franchises::Progress):
    # a member's meters and games for a Franchise, and the members table.
    # Gated by the `franchise_progress` Feature. Any signed-in member reads
    # anyone's progress.
    class FranchiseProgressController < ApplicationController
      feature :franchise_progress

      # GET /api/v1/franchises/:id/progress?user_id=
      #
      # `user_id` defaults to the signed-in member; the bot must name one
      # (400). 404 for an unknown member or Franchise.
      def show
        user_id = params[:user_id].presence || requester_id
        raise ActionController::ParameterMissing, :user_id if user_id.nil?

        user = RpgClubUser.find(user_id)
        render json: { data: progress.for(user.user_id).as_json }
      end

      # GET /api/v1/franchises/:id/progress/members
      def members
        rows = progress.members.map do |row|
          { user: UserSummaryResource.new(row[:user]).serializable_hash, meters: row[:meters],
            conquered_at: row[:conquered_at] }
        end
        render json: { data: rows.as_json }
      end

      private

      def progress = @progress ||= Franchises::Progress.new(GamedbFranchise.find(params[:id]))
    end
  end
end
