# frozen_string_literal: true

# A Linked Account as its owner sees it (users/:user_id/linked_accounts): the
# Provider identity plus its sync state. `sync_available_at` is when Sync now
# is next allowed: now, or the end of the cooldown.
class LinkedAccountResource
  include BaseResource

  attributes :id, :user_id, :provider, :external_id, :display_name, :sync_status, :sync_mode, :sync_error,
    :last_synced_at, :backfilled_at, :sync_requested_at, :created_at

  attribute(:sync_available_at) { |account| account.sync_available_at(params[:now] || Time.current) }
end
