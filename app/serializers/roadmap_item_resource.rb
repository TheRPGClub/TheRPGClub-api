# frozen_string_literal: true

# A Roadmap Item on the Roadmap (spec api#505).
class RoadmapItemResource
  include BaseResource

  attributes :id, :milestone_id, :title, :blurb, :area, :github_issue_url, :position, :shipped_at
end
