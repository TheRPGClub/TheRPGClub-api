# frozen_string_literal: true

# An announceable Unlock as the bot posts it (see Achievements::HighlightOutbox):
# the member, the Achievement, its set and the www set page path. `hidden`
# lets the bot mask a hidden Achievement's name and description.
class AchievementHighlightResource
  include BaseResource

  attributes :id, :highlight, :hardcore, :user_id
  # The Highlight's date: a Mastery's hardcore time, otherwise unlocked_at.
  attribute(:unlocked_at, &:highlight_time)

  attribute :display_name do |unlock|
    unlock.user.global_name.presence || unlock.user.username.presence || unlock.user_id
  end

  attribute :url_path do |unlock|
    "/members/#{unlock.user_id}/achievements/#{unlock.achievement.achievement_set_id}"
  end

  attribute :achievement do |unlock|
    achievement = unlock.achievement
    {
      id: achievement.id, name: achievement.name, description: achievement.description, hidden: achievement.hidden,
      icon_url: achievement.icon_url, tier: achievement.tier, points: achievement.points,
      rarity: achievement.rarity&.to_f
    }
  end

  attribute :achievement_set do |unlock|
    set = unlock.achievement.achievement_set
    { id: set.id, title: set.title, provider: set.provider, platform_label: set.platform_label, icon_url: set.icon_url }
  end
end
