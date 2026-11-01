# frozen_string_literal: true

# An Achievement on a GameDB game's showcase: the definition, the user_ids of
# the active members who unlocked it (`holders`) and whether the signed-in
# viewer has (`viewer_unlocked`). A hidden one keeps its name and description;
# www blurs it. Params: `holders` ({ achievement_id => [user_id] }) and
# `viewer_unlocked_ids` (a Set).
class GameSetAchievementResource
  include BaseResource

  attributes :id, :name, :description, :icon_url, :icon_locked_url, :hidden, :tier, :points

  attribute(:rarity) { |achievement| achievement.rarity&.to_f }
  attribute(:holders) { |achievement| params.fetch(:holders, {}).fetch(achievement.id, []) }
  attribute(:viewer_unlocked) { |achievement| params.fetch(:viewer_unlocked_ids, Set.new).include?(achievement.id) }
end
