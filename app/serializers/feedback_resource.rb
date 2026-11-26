# frozen_string_literal: true

# Serializes a RpgClubFeedback (all columns) plus its upvote count and
# whether the viewer upvoted it, and approved Feedback's GitHub issue
# state (cached; see Github::IssueStateCache). Load records through
# `RpgClubFeedback.with_upvotes(viewer_id)` so both are present.
class FeedbackResource
  include BaseResource

  # approval_started_at is approve's internal bookkeeping; done_notified_at
  # the Done notice's; the screenshot's storage key is served as
  # `screenshot_url`.
  columns_of RpgClubFeedback, except: %w[approval_started_at done_notified_at screenshot_key]

  # A Bug Report's screenshot, nil without one.
  attribute :screenshot_url, &:screenshot_url

  # Approved with its GitHub issue closed (RpgClubFeedback#done?). Done
  # Feedback stays on the board's Open filter, marked Done, and takes no
  # upvotes.
  attribute :done do |feedback|
    feedback.done?
  end

  attribute :upvote_count do |feedback|
    feedback.attributes["upvote_count"].to_i
  end

  attribute :viewer_upvoted do |feedback|
    feedback.attributes["viewer_upvoted"] == true
  end

  # The newest of the row's last change and its newest upvote (see
  # RpgClubFeedback.with_upvotes); `sort=recent` orders by it.
  attribute :last_activity_at do |feedback|
    feedback.attributes["last_activity_at"]
  end

  # "open" or "closed" for approved Feedback's issue; nil otherwise, or
  # when GitHub cannot say. A list passes the page's states, read at once
  # (`github_issue_states`, see FeedbackResource.issue_states).
  attribute :github_issue_state do |feedback|
    next unless feedback.status == "approved"

    pair = [ feedback.target_repo, feedback.github_issue_number ]
    states = params[:github_issue_states]
    states ? states[pair] : Github::IssueStateCache.state_for(*pair)
  end

  # The cached issue states for a page of Feedback, in one cache read (a
  # `prepare:` for render_collection).
  def self.issue_states(records)
    pairs = records.select { |s| s.status == "approved" }.map { |s| [ s.target_repo, s.github_issue_number ] }
    { github_issue_states: Github::IssueStateCache.states_for(pairs) }
  end
end
