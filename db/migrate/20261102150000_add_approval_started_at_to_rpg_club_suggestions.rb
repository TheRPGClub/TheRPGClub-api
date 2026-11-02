# frozen_string_literal: true

# When an approve request claimed the Suggestion before calling GitHub (web
# parity 2 review). Set under a short row lock and cleared when the approval
# finishes or fails, so a second approval while the first is still talking
# to GitHub is refused with 409, without holding the lock across the call.
# A mark older than the in-progress window is from a request that died.
class AddApprovalStartedAtToRpgClubSuggestions < ActiveRecord::Migration[8.1]
  def change
    add_column :rpg_club_suggestions, :approval_started_at, :timestamptz
  end
end
