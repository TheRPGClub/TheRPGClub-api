# frozen_string_literal: true

# An Achievement on the set page, with the subject member's Unlock state
# (`unlocked_at`, `hardcore`; null/false when locked or with no member) and
# whether the signed-in viewer has unlocked it (`viewer_unlocked`, for spoiler
# blur). Params: `unlocks` ({ achievement_id => UserAchievementUnlock }) and
# `viewer_unlocked_ids` (a Set).
class SetAchievementResource
  include BaseResource
  include AchievementFields

  attribute(:unlocked_at) { |achievement| params.fetch(:unlocks, {})[achievement.id]&.unlocked_at }
  attribute(:hardcore) { |achievement| params.fetch(:unlocks, {})[achievement.id]&.hardcore || false }
  attribute(:viewer_unlocked) { |achievement| params.fetch(:viewer_unlocked_ids, Set.new).include?(achievement.id) }
end
