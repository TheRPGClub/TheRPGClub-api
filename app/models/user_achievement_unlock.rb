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
end
