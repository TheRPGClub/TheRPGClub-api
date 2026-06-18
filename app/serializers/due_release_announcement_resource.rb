# frozen_string_literal: true

# A single row of the release-announcements "due" feed
# (ReleaseAnnouncementsController#due): the announcement joined to its release,
# game and platform. Not a plain model dump — the controller hands in rows
# projected off a join (`gamedb_releases`, `gamedb_games`, `gamedb_platforms`),
# so this reads the aliased columns the same way CompletionLeaderboardEntryResource
# reads its grouped aggregates.
#
# `id` and `release_id` are the same value (the announcement PK is the
# release_id, 1:1) — both are exposed because the bot PATCHes
# `/release_announcements/:id` after posting and the issue contract lists both.
class DueReleaseAnnouncementResource
  include BaseResource

  attribute(:id) { |row| row["release_id"] }
  attribute(:release_id) { |row| row["release_id"] }
  attribute(:game_id) { |row| row["game_id"] }
  attribute(:title) { |row| row["title"] }
  attribute(:release_date) { |row| row["release_date"] }
  attribute(:announce_at) { |row| row["announce_at"] }
  attribute(:platform_name) { |row| row["platform_name"] }
  attribute(:platform_abbreviation) { |row| row["platform_abbreviation"] }
  attribute(:igdb_url) { |row| row["igdb_url"] }
end
