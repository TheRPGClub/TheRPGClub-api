# frozen_string_literal: true

module Api
  module V1
    # Staff editing of Roadmap Items (spec api#505, ticket api#507): Admins
    # and Superadmins only. The rules are Roadmap::Items'.
    class RoadmapItemsController < ApplicationController
      feature :roadmap
      include RoadmapRendering

      before_action :require_admin_or_above!

      # POST /api/v1/roadmap/items
      # Body: { "data": { "milestone_id", "title", "blurb", "area", "github_issue_url" } }
      def create
        render_item(Roadmap::Items.create!(request_data), status: :created)
      end

      # PATCH /api/v1/roadmap/items/:id
      def update
        render_item(Roadmap::Items.update!(item, request_data))
      end

      # DELETE /api/v1/roadmap/items/:id
      def destroy
        Roadmap::Items.destroy!(item)
        render json: { data: { id: item.id, deleted: true } }
      end

      # PUT /api/v1/roadmap/items/:id/move
      # Body: { "data": { "milestone_id": <open Milestone>, "position": <from 1> } }
      def move
        Roadmap::Items.move!(item, request_data["milestone_id"], request_data["position"])
        render_roadmap
      end

      # POST /api/v1/roadmap/items/:id/ship
      def ship
        render_item(Roadmap::Items.ship!(item))
      end

      # DELETE /api/v1/roadmap/items/:id/ship
      def unship
        render_item(Roadmap::Items.unship!(item))
      end

      private

      def item
        @item ||= RoadmapItem.find(params[:id])
      end

      def render_item(record, status: :ok)
        render json: { data: RoadmapItemResource.new(record, params: roadmap_params).serializable_hash }, status: status
      end
    end
  end
end
