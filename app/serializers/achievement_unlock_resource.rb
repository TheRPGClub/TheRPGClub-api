# frozen_string_literal: true

# An Unlock with its Achievement and Achievement Set. `viewer_unlocked` says
# whether the signed-in viewer has unlocked the same Achievement, so www can
# blur hidden ones; pass the viewer's unlocked Achievement ids as the
# `viewer_unlocked_ids` param (a Set). Load records with
# `includes(achievement: :achievement_set)`.
class AchievementUnlockResource
  include BaseResource

  attributes :id, :user_id, :unlocked_at, :hardcore, :highlight

  attribute(:viewer_unlocked) { |unlock| params.fetch(:viewer_unlocked_ids, Set.new).include?(unlock.achievement_id) }

  one :achievement, resource: AchievementResource
  attribute(:achievement_set) { |unlock| AchievementSetResource.new(unlock.achievement.achievement_set).serializable_hash }
end
