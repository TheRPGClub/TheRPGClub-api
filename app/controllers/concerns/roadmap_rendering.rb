# frozen_string_literal: true

# Renders the Roadmap (spec api#505) for its read and staff editing
# endpoints, and a Roadmap::Refused as 422 `{ error: code, message: }`.
module RoadmapRendering
  extend ActiveSupport::Concern

  included do
    rescue_from Roadmap::Refused do |error|
      render json: { error: error.code, message: error.message }, status: :unprocessable_content
    end
  end

  private

  # `milestones`: the open Milestones in staff order; `reached`: the Reached
  # ones, newest Reached first. Each carries its Roadmap Items in staff order.
  def render_roadmap
    render json: {
      data: {
        milestones: RoadmapMilestoneResource.new(RoadmapMilestone.open.includes(:items)).serializable_hash,
        reached: RoadmapMilestoneResource.new(RoadmapMilestone.reached.includes(:items)).serializable_hash
      }
    }
  end
end
