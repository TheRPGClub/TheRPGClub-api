# frozen_string_literal: true

module Api
  module V1
    # The Roadmap (GLOSSARY.md "Roadmap"; spec api#505, ticket api#506).
    # Members (any signed-in caller), gated by the Roadmap Feature; staff
    # write it through the editing endpoints.
    class RoadmapController < ApplicationController
      feature :roadmap

      # GET /api/v1/roadmap
      # `milestones`: the open Milestones in staff order; `reached`: the
      # Reached ones, newest Reached first. Each carries its Roadmap Items in
      # staff order.
      def show
        render json: {
          data: {
            milestones: serialize(RoadmapMilestone.open),
            reached: serialize(RoadmapMilestone.reached)
          }
        }
      end

      private

      def serialize(scope)
        RoadmapMilestoneResource.new(scope.includes(:items)).serializable_hash
      end
    end
  end
end
