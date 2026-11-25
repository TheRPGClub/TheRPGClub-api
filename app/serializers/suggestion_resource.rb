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

  # The newest of the row's last change and its newest upvote (see
  # RpgClubSuggestion.with_upvotes); `sort=recent` orders by it.
  attribute :last_activity_at do |suggestion|
    suggestion.attributes["last_activity_at"]
  end

  # "open" or "closed" for an approved Suggestion's issue; nil otherwise, or
  # when GitHub cannot say. A list passes the page's states, read at once
  # (`github_issue_states`, see SuggestionResource.issue_states).
  attribute :github_issue_state do |suggestion|
    next unless suggestion.status == "approved"

    pair = [ suggestion.target_repo, suggestion.github_issue_number ]
    states = params[:github_issue_states]
    states ? states[pair] : Github::IssueStateCache.state_for(*pair)
  end

  # The cached issue states for a page of suggestions, in one cache read (a
  # `prepare:` for render_collection).
  def self.issue_states(suggestions)
    pairs = suggestions.select { |s| s.status == "approved" }.map { |s| [ s.target_repo, s.github_issue_number ] }
    { github_issue_states: Github::IssueStateCache.states_for(pairs) }
  end
end
