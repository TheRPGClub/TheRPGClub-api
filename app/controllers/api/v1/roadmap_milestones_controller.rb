# frozen_string_literal: true

module Api
  module V1
    # Staff editing of the Roadmap's Milestones (spec api#505, ticket
    # api#507): Admins and Superadmins only. The rules are Roadmap::Milestones'.
    class RoadmapMilestonesController < ApplicationController
      feature :roadmap
      include RoadmapRendering

      before_action :require_admin_or_above!

      # POST /api/v1/roadmap/milestones
      # Body: { "data": { "name", "blurb", "target_date", "date_precision" } }
      def create
        render_milestone(Roadmap::Milestones.create!(request_data), status: :created)
      end

      # PATCH /api/v1/roadmap/milestones/:id
      def update
        render_milestone(Roadmap::Milestones.update!(milestone, request_data))
      end

      # DELETE /api/v1/roadmap/milestones/:id
      # Refused (422 `milestone_has_items`) while it has Roadmap Items.
      def destroy
        Roadmap::Milestones.destroy!(milestone)
        render json: { data: { id: milestone.id, deleted: true } }
      end

      # PUT /api/v1/roadmap/milestones/order
      # Body: { "data": { "milestone_ids": [<every open Milestone id>] } }
      def order
        Roadmap::Milestones.reorder!(request_data["milestone_ids"])
        render_roadmap
      end

      # PUT /api/v1/roadmap/milestones/:id/items/order
      # Body: { "data": { "item_ids": [<every item id of the Milestone>] } }
      def order_items
        Roadmap::Items.reorder!(milestone, request_data["item_ids"])
        render_roadmap
      end

      # POST /api/v1/roadmap/milestones/:id/reach
      # Body (optional): { "data": { "destination_milestone_id": <id> } }
      def reach
        Roadmap::Milestones.reach!(milestone, optional_data["destination_milestone_id"])
        render_roadmap
      end

      # DELETE /api/v1/roadmap/milestones/:id/reach
      def unreach
        Roadmap::Milestones.unreach!(milestone)
        render_roadmap
      end

      private

      def milestone
        @milestone ||= RoadmapMilestone.find(params[:id])
      end

      def optional_data
        params[:data].present? ? request_data : {}
      end

      def render_milestone(record, status: :ok)
        record = RoadmapMilestone.includes(items: :feedback).find(record.id)
        render json: { data: RoadmapMilestoneResource.new(record).serializable_hash }, status: status
      end
    end
  end
end
