# frozen_string_literal: true

module Achievements
  # The base scopes every Achievement Hub read starts from, so the exclusions
  # live in one place: departed members, placeholder progress rows
  # (`synced_at` nil) and removed Achievements never appear.
  module Reads
    PROVIDERS = UserLinkedAccount::PROVIDERS

    module_function

    # Progress rows of active members that have been imported at least once.
    def progress
      UserAchievementSetProgress.synced.of_active_members
    end

    # Unlocks of active members on non-removed Achievements.
    def unlocks
      UserAchievementUnlock.of_active_members.joins(:achievement).merge(Achievement.active)
    end

    # The ids, among `achievement_ids`, of the Achievements the viewer has
    # unlocked, for spoiler blur. Empty for a non-member principal.
    def viewer_unlocked_ids(viewer_id, achievement_ids)
      return Set.new if viewer_id.blank? || achievement_ids.empty?

      UserAchievementUnlock.where(user_id: viewer_id, achievement_id: achievement_ids.uniq).pluck(:achievement_id).to_set
    end
  end
end
