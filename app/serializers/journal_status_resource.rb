# frozen_string_literal: true

# A single game's journal status for one user (JournalController#status): the
# game id plus the user's `entry_count` and `last_entry_at`. Mirrors the bot's
# `getJournalStatusForGames`. Not a plain model record — the controller hands
# in grouped/aggregated rows (`gamedb_game_id` plus the `COUNT(*)` /
# `MAX(created_at)` aliases), so this reads the selected attributes the same way
# JournaledGameResource serializes its grouped aggregates.
class JournalStatusResource
  include BaseResource

  attribute :gamedb_game_id do |row|
    row["gamedb_game_id"].to_i
  end

  attribute :entry_count do |row|
    row["entry_count"].to_i
  end

  attribute :last_entry_at do |row|
    row["last_entry_at"]
  end
end
