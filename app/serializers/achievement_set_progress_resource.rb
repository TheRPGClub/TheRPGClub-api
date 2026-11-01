# frozen_string_literal: true

# A member's cached progress on one Achievement Set, with the set embedded.
# `provider` repeats the set's Provider for convenience. Load records with
# `includes(:achievement_set)`.
class AchievementSetProgressResource
  include BaseResource

  attributes :id, :user_id, :earned_count, :hardcore_earned_count, :total_count, :points_earned,
             :completed_at, :mastered_at, :platinum_at, :last_unlocked_at, :playtime_minutes

  attribute(:provider) { |progress| progress.achievement_set.provider }
  one :achievement_set, resource: AchievementSetResource
end
