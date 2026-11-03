# frozen_string_literal: true

# A claimed bot job as the bot receives it: the status fields plus the
# per-kind payload it acts on.
class BotJobClaimResource
  include BaseResource

  attributes :id, :kind, :payload, :status, :requested_by_user_id, :attempts, :error_message, :claimed_at,
             :finished_at, :created_at, :updated_at
end
