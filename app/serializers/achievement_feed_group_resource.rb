# frozen_string_literal: true

# A `latest` feed card (Achievements::Feed::Group): one member's Unlocks in one
# Achievement Set on one UTC day, with the day's count and up to 8 of the
# newest Unlocks. Pass `viewer_unlocked_ids` for the Unlocks' spoiler blur.
class AchievementFeedGroupResource
  include BaseResource

  attribute(:kind) { |_group| "group" }
  attribute(:user) { |group| UserSummaryResource.new(group.user).serializable_hash }
  attribute(:achievement_set) { |group| AchievementSetResource.new(group.achievement_set).serializable_hash }
  attribute(:day) { |group| group.day.iso8601 }
  attributes :count, :latest_unlocked_at
  attribute(:unlocks) { |group| AchievementUnlockResource.new(group.unlocks, params: params).serializable_hash }
end
