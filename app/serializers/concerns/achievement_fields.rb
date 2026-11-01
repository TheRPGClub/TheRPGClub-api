# frozen_string_literal: true

# An Achievement definition's public columns, shared by AchievementResource and
# the set page's SetAchievementResource. Rarity is the Provider's global
# figure, rendered as a number (decimal columns would otherwise serialise as
# strings).
module AchievementFields
  extend ActiveSupport::Concern

  included do
    attributes :id, :name, :description, :icon_url, :icon_locked_url, :hidden, :points, :tier,
               :display_order, :removed_at

    attribute(:rarity) { |achievement| achievement.rarity&.to_f }
    attribute(:rarity_hardcore) { |achievement| achievement.rarity_hardcore&.to_f }
  end
end
