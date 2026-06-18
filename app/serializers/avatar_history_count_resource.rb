# frozen_string_literal: true

# A single row of the avatar-history leaderboard
# (UserAvatarHistoryController#counts): a member's identity plus the total
# number of avatar changes the bot has logged for them. Not a plain model
# record — the controller hands in the grouped/aggregated rows (the user
# identity columns selected off `rpg_club_users` plus the `COUNT(*)`
# `avatar_change_count` alias), so this reads those selected attributes the same
# way CompletionLeaderboardEntryResource serializes its grouped aggregates.
class AvatarHistoryCountResource
  include BaseResource

  attributes :user_id, :username, :global_name

  attribute :avatar_change_count do |row|
    row["avatar_change_count"].to_i
  end
end
