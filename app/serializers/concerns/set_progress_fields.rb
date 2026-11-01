# frozen_string_literal: true

# The cached progress columns of a member's Achievement Set progress row,
# shared by the bare SetProgressResource and the grid's
# AchievementSetProgressResource (which embeds the set).
module SetProgressFields
  extend ActiveSupport::Concern

  included do
    attributes :id, :user_id, :achievement_set_id, :earned_count, :hardcore_earned_count, :total_count,
               :points_earned, :completed_at, :mastered_at, :platinum_at, :last_unlocked_at, :playtime_minutes
  end
end
