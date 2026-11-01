# frozen_string_literal: true

# A `highlights` feed card: one Highlight Unlock with its member. Params:
# `users` ({ user_id => RpgClubUser }) and `viewer_unlocked_ids`.
class AchievementFeedHighlightResource
  include BaseResource

  attribute(:kind) { |_unlock| "highlight" }
  attributes :id, :user_id, :unlocked_at, :hardcore, :highlight

  attribute(:viewer_unlocked) { |unlock| params.fetch(:viewer_unlocked_ids, Set.new).include?(unlock.achievement_id) }
  one :achievement, resource: AchievementResource
  attribute(:achievement_set) { |unlock| AchievementSetResource.new(unlock.achievement.achievement_set).serializable_hash }
  attribute(:user) { |unlock| UserSummaryResource.new(params.fetch(:users)[unlock.user_id]).serializable_hash }
end
