# frozen_string_literal: true

# Dashboard Panels (spec api#421, ticket api#422; docs/adr/0012): the panels a
# member shows below the current issue on their own dashboard, in their order.
# A member with no saved list follows the club default
# (DashboardPanels::DEFAULT); their first save writes their whole list and
# sets `dashboard_panels_customised`, so a member who hid every panel keeps an
# empty list rather than falling back to the default. `panel_key` is a
# DashboardPanels key, not tied to any other table, so a panel survives its
# Feature being hidden for a while. `dashboard_panels_seen_at` is when the
# member last opened edit mode; panels added after it are new to them.
class CreateMemberDashboardPanels < ActiveRecord::Migration[8.1]
  def change
    create_table :member_dashboard_panels do |t|
      t.string :user_id, limit: 30, null: false
      t.string :panel_key, limit: 64, null: false
      t.integer :position, null: false
      t.datetime :created_at, null: false
    end

    add_index :member_dashboard_panels, %i[user_id panel_key], unique: true
    add_foreign_key :member_dashboard_panels, :rpg_club_users, column: :user_id, primary_key: :user_id,
      on_delete: :cascade

    add_column :rpg_club_users, :dashboard_panels_customised, :boolean, default: false, null: false,
      comment: "Whether the member saved their own Dashboard Panels; false follows the club default."
    add_column :rpg_club_users, :dashboard_panels_seen_at, :datetime,
      comment: "When the member last opened dashboard edit mode; panels added after it are new to them."
  end
end
