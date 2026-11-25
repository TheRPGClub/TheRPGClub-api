# frozen_string_literal: true

# Indexes for the orders the hottest per-member and club-wide reads sort by
# (query sweep, 2026-11-25):
# - a member's completions newest first (CompletionsController#index, the
#   profile preview, the months tally), previously sorted from ix_ugc_user;
# - the club's Recent Completions feed (CompletionsController#recent), which
#   sorted every completion on every request;
# - a member's unlocks newest first (MemberAchievementsController#unlocks,
#   Achievements::MemberSummary's latest), which sorted from the
#   (user_id, achievement_id) unique index.
# Built concurrently so the tables stay writable while they build.
class AddCompletionAndUnlockOrderIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :user_game_completions, [ :user_id, :completed_at, :created_at ],
      order: { completed_at: :desc, created_at: :desc },
      name: :ix_ugc_user_completed_at, if_not_exists: true, algorithm: :concurrently
    add_index :user_game_completions, [ :completed_at, :created_at, :completion_id ],
      order: { completed_at: "DESC NULLS LAST", created_at: :desc, completion_id: :desc },
      name: :ix_ugc_recent, if_not_exists: true, algorithm: :concurrently
    add_index :user_achievement_unlocks, [ :user_id, :unlocked_at, :id ],
      order: { unlocked_at: :desc, id: :desc },
      name: :ix_user_achievement_unlocks_user_unlocked_at, if_not_exists: true, algorithm: :concurrently
  end

  def down
    remove_index :user_game_completions, name: :ix_ugc_user_completed_at, if_exists: true, algorithm: :concurrently
    remove_index :user_game_completions, name: :ix_ugc_recent, if_exists: true, algorithm: :concurrently
    remove_index :user_achievement_unlocks, name: :ix_user_achievement_unlocks_user_unlocked_at,
      if_exists: true, algorithm: :concurrently
  end
end
