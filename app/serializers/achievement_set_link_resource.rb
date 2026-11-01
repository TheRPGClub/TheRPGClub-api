# frozen_string_literal: true

# An Achievement Set and its GameDB link, returned by the admin link fix
# (PATCH /api/v1/achievement_sets/:id).
class AchievementSetLinkResource
  include BaseResource

  attributes :id, :provider, :external_id, :title, :platform_label, :icon_url, :game_id
end
