# frozen_string_literal: true

# Feedback Board (spec api#498, ticket api#502): Approved Feedback whose
# GitHub issue is closed is Done. `done_at` mirrors the issue's last seen
# state (set when Github::IssueStateRefreshJob sees it closed, cleared when it
# sees it open again), so the board can filter and freeze upvotes without
# GitHub. `done_notified_at` records the one Done notice sent to the author
# and is never cleared, so reopening and closing again sends nothing.
#
# Feedback already Approved before the Done notice existed is marked
# notified: its first refresh would otherwise announce every issue closed
# long ago.
class AddDoneToFeedback < ActiveRecord::Migration[8.1]
  def up
    add_column :rpg_club_feedback, :done_at, :timestamptz
    add_column :rpg_club_feedback, :done_notified_at, :timestamptz
    execute "UPDATE rpg_club_feedback SET done_notified_at = statement_timestamp() WHERE status = 'approved'"
  end

  def down
    remove_column :rpg_club_feedback, :done_notified_at
    remove_column :rpg_club_feedback, :done_at
  end
end
