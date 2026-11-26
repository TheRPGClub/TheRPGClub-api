# frozen_string_literal: true

# A Roadmap Item on the Roadmap (spec api#505).
class RoadmapItemResource
  include BaseResource

  attributes :id, :milestone_id, :title, :blurb, :area, :github_issue_url, :position, :shipped_at

  # Its linked Feedback (ticket api#508), oldest first: enough to show and
  # link to each. Empty unless the caller passes `feedback_usable: true`
  # (RoadmapRendering#roadmap_params): a viewer who can't use the Feedback
  # Feature sees none of it.
  attribute :feedback do |item|
    next [] unless params[:feedback_usable]

    item.feedback.map do |feedback|
      { id: feedback.feedback_id, title: feedback.title, kind: feedback.kind, status: feedback.status,
        done: feedback.done? }
    end
  end
end
