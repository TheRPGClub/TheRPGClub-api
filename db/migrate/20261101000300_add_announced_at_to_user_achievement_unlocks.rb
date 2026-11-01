# frozen_string_literal: true

# The bot acks each Highlight it posts (`announced_at`) instead of moving an id
# cursor: Unlock ids become visible at COMMIT, out of id order across the
# concurrent Provider chains, so a cursor could skip one for good. Unlocks a
# stored cursor already covered count as announced.
class AddAnnouncedAtToUserAchievementUnlocks < ActiveRecord::Migration[8.1]
  def up
    add_column :user_achievement_unlocks, :announced_at, :datetime
    execute <<~SQL.squish
      UPDATE user_achievement_unlocks SET announced_at = now()
      WHERE announceable
        AND id <= (SELECT (value #>> '{}')::bigint FROM achievement_hub_states WHERE key = 'bot_highlight_cursor')
    SQL
    execute "DELETE FROM achievement_hub_states WHERE key = 'bot_highlight_cursor'"

    remove_index :user_achievement_unlocks, name: "ix_user_achievement_unlocks_announceable"
    add_index :user_achievement_unlocks, :id, where: "announceable AND announced_at IS NULL",
      name: "ix_user_achievement_unlocks_unannounced"
  end

  def down
    remove_index :user_achievement_unlocks, name: "ix_user_achievement_unlocks_unannounced"
    add_index :user_achievement_unlocks, :id, where: "announceable", name: "ix_user_achievement_unlocks_announceable"
    remove_column :user_achievement_unlocks, :announced_at
  end
end
