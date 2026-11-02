# frozen_string_literal: true

# Per-request state, reset by Rails after every request (and job).
class Current < ActiveSupport::CurrentAttributes
  # GitHub issue state lookups this request has made (see Github::IssueStateCache).
  attribute :github_issue_lookups
end
