# frozen_string_literal: true

# An Achievement: a single goal a Provider defines in an Achievement Set,
# shared by every member. PSN trophies carry a `tier`; RA ones carry `points`
# and a hardcore Rarity. An Achievement the Provider stops reporting gets
# `removed_at` and is never deleted, because deleting it would cascade to every
# member's Unlocks.
class Achievement < ApplicationRecord
  TIERS = %w[bronze silver gold platinum].freeze

  enum :tier, TIERS.index_with(&:itself), validate: { allow_nil: true }

  belongs_to :achievement_set, inverse_of: :achievements
  has_many :unlocks,
    class_name: "UserAchievementUnlock",
    dependent: nil, # on delete cascade
    inverse_of: :achievement

  validates :external_id, presence: true, uniqueness: { scope: :achievement_set_id }

  scope :active, -> { where(removed_at: nil) }
end
