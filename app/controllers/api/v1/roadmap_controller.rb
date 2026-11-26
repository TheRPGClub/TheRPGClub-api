# frozen_string_literal: true

module Api
  module V1
    # The Roadmap (GLOSSARY.md "Roadmap"; spec api#505, ticket api#506).
    # Members (any signed-in caller), gated by the Roadmap Feature; staff
    # write it through RoadmapMilestonesController and RoadmapItemsController.
    class RoadmapController < ApplicationController
      feature :roadmap
      include RoadmapRendering

      # GET /api/v1/roadmap
      def show
        render_roadmap
      end
    end
  end
end
