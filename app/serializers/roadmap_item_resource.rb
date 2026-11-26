# frozen_string_literal: true

# A Roadmap Item on the Roadmap (spec api#505).
class RoadmapItemResource
  include BaseResource

  attributes :id, :milestone_id, :title, :blurb, :area, :github_issue_url, :position, :shipped_at

  # Its linked Feedback (ticket api#508), oldest first: enough to show and
  # link to each.
  attribute :feedback do |item|
    item.feedback.map do |feedback|
      { id: feedback.feedback_id, title: feedback.title, kind: feedback.kind, status: feedback.status,
        done: feedback.done? }
    end
  end
end
