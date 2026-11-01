# frozen_string_literal: true

# An Unlock: the fact that a member earned an Achievement, and when. RA Unlocks
# are hardcore or softcore. `highlight` and `announceable` are set by the sync
# on newly inserted Unlocks only (see .classify_highlight).
class UserAchievementUnlock < ApplicationRecord
  HIGHLIGHTS = %w[platinum completion mastery rare].freeze

  enum :highlight, HIGHLIGHTS.index_with(&:itself), validate: { allow_nil: true }

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    inverse_of: :achievement_unlocks
  belongs_to :achievement, inverse_of: :unlocks
  belongs_to :linked_account,
    class_name: "UserLinkedAccount",
    foreign_key: :user_linked_account_id,
    inverse_of: :unlocks

  validates :unlocked_at, presence: true
  validates :achievement_id, uniqueness: { scope: :user_id }

  RARE_BELOW = 5.0

  scope :of_active_members, -> { where(user_id: RpgClubUser.active.select(:user_id)) }

  # Which Highlight an Unlock is, given the member's progress on its set after
  # the sync (see UserAchievementSetProgress.recompute!), or nil. Precedence:
  # platinum > mastery > completion > rare. Completion and Mastery belong to
  # the Unlock whose time stamped them, i.e. the one that produced them.
  def self.classify_highlight(unlock, progress_after:)
    achievement = unlock.achievement
    return "platinum" if achievement.tier == "platinum"
    if unlock.hardcore? && achievement.achievement_set.retroachievements? &&
        progress_after.mastered_at.present? && progress_after.mastered_at == unlock.unlocked_at
      return "mastery"
    end
    return "completion" if progress_after.completed_at.present? && progress_after.completed_at == unlock.unlocked_at

    "rare" if achievement.rarity.present? && achievement.rarity < RARE_BELOW
  end
end
