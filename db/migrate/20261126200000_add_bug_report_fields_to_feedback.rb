# frozen_string_literal: true

# Bug Report fields and screenshot (spec api#498, ticket api#500). A Bug
# Report says where it happened (bot or website), what happened, what was
# expected and, optionally, the steps to reproduce; it may carry one
# screenshot, kept in B2 under `screenshot_key`. The other kinds leave them
# empty.
class AddBugReportFieldsToFeedback < ActiveRecord::Migration[8.1]
  def change
    change_table :rpg_club_feedback, bulk: true do |t|
      t.string :where, limit: 16
      t.string :what_happened, limit: 2000
      t.string :expected, limit: 2000
      t.string :steps, limit: 2000
      t.string :screenshot_key, limit: 500
    end
    add_check_constraint :rpg_club_feedback, "\"where\" IS NULL OR \"where\" IN ('bot', 'website')",
      name: "ck_rpg_club_feedback_where"
  end
end
