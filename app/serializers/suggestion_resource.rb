# frozen_string_literal: true

# Serializes a RpgClubSuggestion (all columns) plus its upvote count and
# whether the viewer upvoted it, and an approved Suggestion's GitHub issue
# state (cached; see Github::IssueStateCache). Load records through
# `RpgClubSuggestion.with_upvotes(viewer_id)` so both are present.
class SuggestionResource
  include BaseResource

  # approval_started_at is approve's internal bookkeeping.
  columns_of RpgClubSuggestion, except: %w[approval_started_at]

  attribute :upvote_count do |suggestion|
    suggestion.attributes["upvote_count"].to_i
  end

  attribute :viewer_upvoted do |suggestion|
    suggestion.attributes["viewer_upvoted"] == true
  end

  # "open" or "closed" for an approved Suggestion's issue; nil otherwise, or
  # when GitHub cannot say.
  attribute :github_issue_state do |suggestion|
    if suggestion.status == "approved"
      Github::IssueStateCache.fetch(suggestion.target_repo, suggestion.github_issue_number)
    end
  end
end
