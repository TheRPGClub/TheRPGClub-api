# frozen_string_literal: true

# RA reports a softcore and a hardcore date per Unlock; `unlocked_at` keeps
# the first earn, and Mastery is dated by the hardcore one.
class AddHardcoreUnlockedAtToUserAchievementUnlocks < ActiveRecord::Migration[8.1]
  def change
    add_column :user_achievement_unlocks, :hardcore_unlocked_at, :datetime
  end
end
