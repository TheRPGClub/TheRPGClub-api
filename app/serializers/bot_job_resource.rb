# frozen_string_literal: true

# A bot job's status, as the website shows it (see BotJob): what it does in
# plain words, who asked, and how it ended. Leaves out the payload, which
# can hold what the bot delivers (a giveaway key). Preload `requested_by`.
class BotJobResource
  include BaseResource

  attributes :id, :kind
  # Jobs the previous release queued during a deploy have a blank summary.
  attribute(:summary) { |job| job.summary.presence || job.kind.humanize }
  attributes :status, :requested_by_user_id
  one :requested_by, resource: UserSummaryResource
  attributes :attempts, :error_message, :result_text, :claimed_at, :lease_expires_at, :finished_at,
             :created_at, :updated_at
end
