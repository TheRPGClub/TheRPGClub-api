# frozen_string_literal: true

# A single row of the journal contributors list (JournalController#contributors):
# a user's identity plus their distinct journaled-game count (`game_count`) and
# total entry count (`entry_count`). Mirrors the bot's `getAllJournalUsers`. An
# aggregate row, not a model record — the controller hands in the grouped rows
# (the user identity columns selected off `rpg_club_users` plus the two `COUNT`
# aliases), so this reads them the same way CompletionLeaderboardEntryResource
# serializes its grouped aggregates.
class JournalContributorResource
  include BaseResource

  attributes :user_id, :username, :global_name

  attribute :game_count do |row|
    row["game_count"].to_i
  end

  attribute :entry_count do |row|
    row["entry_count"].to_i
  end
end
