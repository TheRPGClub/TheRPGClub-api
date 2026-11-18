# frozen_string_literal: true

# The Club Codex (GLOSSARY.md, "Club Codex"; spec #397): the club's story
# about itself, kept as CodexEntry rows in three parts (Club History, Club
# Lore and Fun Facts). The API owns every rule: who may write and change an
# entry (ClubCodex::Actor) and the members its text mentions
# (ClubCodex::Mentions).
module ClubCodex
  # A member as Club Codex payloads show them (an entry's author, a mentioned
  # member): their id, which is also their profile's, the name they go by now
  # (their Discord display name, else username, else id) and the path of
  # their stored avatar (GET /api/v1/users/{id}/avatar).
  def self.member(user)
    { user_id: user.user_id, name: user.global_name.presence || user.username.presence || user.user_id,
      avatar_url: "/api/v1/users/#{user.user_id}/avatar" }
  end
end
