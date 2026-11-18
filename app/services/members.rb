# frozen_string_literal: true

# How a member is named in JSON and bot payloads (Challenges, Birthdays).
module Members
  module_function

  # A member as the API serves them inside other resources: their names, the
  # Discord avatar hash stored at their last login (null if unknown; with the
  # user id it makes a Discord CDN URL), and the path of the avatar image the
  # bot stores (GET /api/v1/users/{id}/avatar, which 404s when it has none).
  def summary(user)
    { user_id: user.user_id, username: user.username, global_name: user.global_name,
      discord_avatar: user.discord_avatar, avatar_url: "/api/v1/users/#{user.user_id}/avatar" }
  end

  # The name a member goes by: their Discord display name, else their
  # username, else their id.
  def display_name(user) = user.global_name.presence || user.username.presence || user.user_id

  # The order members are listed in by name: display name case-insensitively,
  # then id so ties are stable. A sort_by key.
  def by_name(user) = [ display_name(user).downcase, user.user_id ]
end
