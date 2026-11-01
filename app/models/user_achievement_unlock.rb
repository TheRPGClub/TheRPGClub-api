# frozen_string_literal: true

# An Unlock: the fact that a member earned an Achievement, and when. RA Unlocks
# are hardcore or softcore; `unlocked_at` is the first earn (RA's softcore
# date) and `hardcore_unlocked_at` the hardcore one, which dates a Mastery. `highlight` and `announceable` are set by the sync
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
        progress_after.mastered_at.present? && progress_after.mastered_at == unlock.mastery_time
      return "mastery"
    end
    return "completion" if progress_after.completed_at.present? && progress_after.completed_at == unlock.unlocked_at

    "rare" if achievement.rarity.present? && achievement.rarity < RARE_BELOW
  end

  # When this Unlock counted towards a Mastery: its hardcore date (rows from
  # before that date was stored fall back to unlocked_at).
  def mastery_time
    hardcore_unlocked_at || unlocked_at
  end

  # #highlight_time in SQL, for ordering Highlights.
  HIGHLIGHT_TIME_SQL = "CASE WHEN user_achievement_unlocks.highlight = 'mastery' " \
    "THEN COALESCE(user_achievement_unlocks.hardcore_unlocked_at, user_achievement_unlocks.unlocked_at) " \
    "ELSE user_achievement_unlocks.unlocked_at END"

  # When the Highlight happened: a Mastery's #mastery_time, otherwise
  # unlocked_at. Highlight cards and posts are dated and ordered by it.
  def highlight_time
    mastery? ? mastery_time : unlocked_at
  end
end
