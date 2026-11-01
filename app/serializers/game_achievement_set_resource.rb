# frozen_string_literal: true

# An Achievement Set on a GameDB game's showcase: the set, the members who
# completed it (oldest Completion first) and the viewer's own progress, or
# null. Params: `completions` ({ set_id => [UserAchievementSetProgress] }),
# `users` ({ user_id => RpgClubUser }) and `viewer_progress`
# ({ set_id => UserAchievementSetProgress }).
class GameAchievementSetResource
  include BaseResource

  attributes :id, :provider, :external_id, :title, :platform_label, :icon_url, :game_id,
             :achievements_count, :points_total

  attribute(:completions) do |set|
    params.fetch(:completions).fetch(set.id, []).map do |progress|
      {
        "user" => UserSummaryResource.new(params.fetch(:users)[progress.user_id]).serializable_hash,
        "completed_at" => progress.completed_at
      }
    end
  end

  attribute(:viewer_progress) do |set|
    progress = params.fetch(:viewer_progress)[set.id]
    progress && SetProgressResource.new(progress).serializable_hash
  end
end
