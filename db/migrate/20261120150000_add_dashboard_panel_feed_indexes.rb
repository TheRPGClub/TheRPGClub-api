# frozen_string_literal: true

# Indexes for the Dashboard Panels reads (spec api#421; code review of
# api#428). Challenge Activity (Challenges::Activity) reads the newest Runs
# started, Runs finished and games cleared on every call, and sorted whole
# tables to do it. `member_hidden_platforms.platform_id` cascades from GameDB
# platforms and had no index of its own, so a platform delete scanned it.
class AddDashboardPanelFeedIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :challenge_runs, %i[started_at id], name: "ix_challenge_runs_started"
    add_index :challenge_runs, %i[ended_at id], name: "ix_challenge_runs_finished",
      where: "status = 'finished' AND ended_at IS NOT NULL"
    add_index :challenge_run_entries, %i[cleared_on id], name: "ix_challenge_run_entries_cleared",
      where: "state = 'cleared' AND cleared_on IS NOT NULL"
    add_index :member_hidden_platforms, :platform_id
  end
end
