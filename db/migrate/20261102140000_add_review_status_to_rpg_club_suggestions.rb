# frozen_string_literal: true

# Suggestions are kept with a status instead of being deleted on review (web
# parity 2, #318). Existing rows become pending. The review columns are filled
# when a Superadmin approves (GitHub issue in the target repo) or rejects
# (with a reason); `reviewed_by` is the reviewer's Discord user id.
class AddReviewStatusToRpgClubSuggestions < ActiveRecord::Migration[8.1]
  def change
    change_table :rpg_club_suggestions, bulk: true do |t|
      t.string :status, limit: 16, null: false, default: "pending"
      t.string :reviewed_by, limit: 30
      t.timestamptz :reviewed_at
      t.string :rejection_reason, limit: 2000
      t.string :target_repo, limit: 200
      t.integer :github_issue_number
      t.string :github_issue_url, limit: 500
    end
    add_check_constraint :rpg_club_suggestions,
      "status IN ('pending', 'approved', 'rejected', 'withdrawn')", name: "ck_rpg_club_suggestions_status"
    add_index :rpg_club_suggestions, :status, name: "ix_rpg_club_suggestions_status"
  end
end
