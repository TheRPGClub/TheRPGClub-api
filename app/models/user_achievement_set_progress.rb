# frozen_string_literal: true

# A member's cached progress on one Achievement Set, so reads never aggregate
# over every Unlock. A row with `synced_at` nil is a placeholder waiting for its
# first import and is excluded from every read; `sync_pending_at` marks a set
# waiting for an import (ADR 0003).
class UserAchievementSetProgress < ApplicationRecord
  self.table_name = "user_achievement_set_progress"

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    inverse_of: :achievement_set_progress
  belongs_to :achievement_set, inverse_of: :progress
  belongs_to :linked_account,
    class_name: "UserLinkedAccount",
    foreign_key: :user_linked_account_id,
    inverse_of: :set_progress

  validates :achievement_set_id, uniqueness: { scope: :user_id }

  scope :of_active_members, -> { where(user_id: RpgClubUser.active.select(:user_id)) }
  # Rows that have been imported at least once; every read uses this.
  scope :synced, -> { where.not(synced_at: nil) }
  # The Provider's sets waiting for an import, oldest first.
  scope :sync_pending, lambda { |provider, now = Time.current|
    joins(:linked_account)
      .where(user_linked_accounts: { provider: provider })
      .where(sync_pending_at: ..now)
      .order(:sync_pending_at, :id)
  }

  # Rebuilds the member's cached progress on a set from their Unlocks and the
  # set's non-removed Achievements, and stamps `synced_at`. Completion and
  # Mastery take the time of the Unlock that produced them; Mastery is RA only,
  # needs every Unlock to be hardcore, and is dated by their hardcore dates
  # (RA's softcore date can be years earlier). Creates the row when missing.
  def self.recompute!(user_id:, achievement_set_id:)
    set = AchievementSet.find(achievement_set_id)
    progress = find_or_initialize_by(user_id: user_id, achievement_set_id: set.id)
    progress.user_linked_account_id ||= UserLinkedAccount.find_by!(user_id: user_id, provider: set.provider).id

    total = set.achievements.active.count
    unlocks = UserAchievementUnlock.where(user_id: user_id)
      .joins(:achievement).merge(Achievement.active).where(achievements: { achievement_set_id: set.id })
    earned, hardcore_earned, points, last_at, last_hardcore_at, platinum_at = unlocks.pick(
      Arel.sql("COUNT(*)"),
      Arel.sql("COUNT(*) FILTER (WHERE user_achievement_unlocks.hardcore)"),
      Arel.sql("COALESCE(SUM(achievements.points), 0)"),
      Arel.sql("MAX(user_achievement_unlocks.unlocked_at)"),
      Arel.sql("MAX(COALESCE(user_achievement_unlocks.hardcore_unlocked_at, user_achievement_unlocks.unlocked_at)) " \
               "FILTER (WHERE user_achievement_unlocks.hardcore)"),
      Arel.sql("MAX(user_achievement_unlocks.unlocked_at) FILTER (WHERE achievements.tier = 'platinum')")
    )
    complete = total.positive? && earned == total
    mastered = complete && set.retroachievements? && hardcore_earned == total

    progress.update!(
      earned_count: earned,
      hardcore_earned_count: hardcore_earned,
      total_count: total,
      points_earned: points,
      completed_at: (last_at if complete),
      mastered_at: (last_hardcore_at if mastered),
      platinum_at: platinum_at,
      last_unlocked_at: last_at,
      synced_at: Time.current
    )
    progress
  end
end
