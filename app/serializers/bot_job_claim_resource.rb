# frozen_string_literal: true

# A claimed bot job as the bot receives it: the status fields plus the
# per-kind payload it acts on, and when its claim lease runs out.
class BotJobClaimResource
  include BaseResource

  attributes :id, :kind, :summary, :payload, :status, :requested_by_user_id, :attempts, :error_message,
             :result_text, :claimed_at, :lease_expires_at, :finished_at, :created_at, :updated_at
end
