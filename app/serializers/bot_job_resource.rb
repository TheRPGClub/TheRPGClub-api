# frozen_string_literal: true

# A bot job's status, as the website shows it (see BotJob). Leaves out the
# payload, which can hold what the bot delivers (a giveaway key).
class BotJobResource
  include BaseResource

  attributes :id, :kind, :status, :requested_by_user_id, :attempts, :error_message, :claimed_at,
             :finished_at, :created_at, :updated_at
end
