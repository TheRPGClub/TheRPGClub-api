# frozen_string_literal: true

# Dashboard Panels "New" marker (spec api#421; code review of api#428): keeps
# which panels the member has seen instead of when they last opened edit mode.
# A time compared with a panel's typed-in `added_on` missed panels that
# deployed days after that date, for anyone who opened edit mode in between.
# NULL means the member never opened edit mode: they have seen the launch
# panels (DashboardPanels::LAUNCH_KEYS) and nothing added since.
class ReplaceDashboardPanelsSeenAtWithSeenKeys < ActiveRecord::Migration[8.1]
  def change
    remove_column :rpg_club_users, :dashboard_panels_seen_at, :datetime,
      comment: "When the member last opened dashboard edit mode; panels added after it are new to them."
    add_column :rpg_club_users, :dashboard_panels_seen_keys, :string, array: true,
      comment: "Dashboard Panel keys the member has seen in edit mode; NULL until they first open it."
  end
end
