# frozen_string_literal: true

# An Achievement Set as the hub's reads embed it: the Provider's list for one
# title, with its optional GameDB link (`game_id`).
class AchievementSetResource
  include BaseResource

  attributes :id, :provider, :external_id, :title, :platform_label, :icon_url, :game_id,
             :achievements_count, :points_total
end
