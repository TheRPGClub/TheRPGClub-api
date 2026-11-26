# frozen_string_literal: true

# A Milestone on the Roadmap with its Roadmap Items in staff order (spec
# api#505). `target_date` is a plain date at its Date Precision, null for TBA.
class RoadmapMilestoneResource
  include BaseResource

  attributes :id, :name, :blurb
  attribute(:target_date) { |milestone| milestone.target_date&.iso8601 }
  attributes :date_precision, :position, :reached_at
  many :items, resource: RoadmapItemResource
end
