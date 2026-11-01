# frozen_string_literal: true

# An Achievement definition, shared by every member (ADR 0001). Rarity is the
# Provider's global figure, as a number (the decimal columns would otherwise
# serialise as strings). `removed_at` is set once the Provider stopped
# reporting it.
class AchievementResource
  include BaseResource

  attributes :id, :name, :description, :icon_url, :icon_locked_url, :hidden, :points, :tier,
             :display_order, :removed_at

  attribute(:rarity) { |achievement| achievement.rarity&.to_f }
  attribute(:rarity_hardcore) { |achievement| achievement.rarity_hardcore&.to_f }
end
