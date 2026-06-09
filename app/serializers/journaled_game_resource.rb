# frozen_string_literal: true

# A single journaled game for the user-journal grid: the game summary plus the
# user's per-game `entry_count` and `last_entry_at`. Shared by the grid
# endpoint (journal#index) and the profile preview (UserResource), so the two
# never drift apart. Each serialized record is a GamedbGame carrying the
# aggregate columns selected by `UserGameJournalEntry.journaled_games_for`.
class JournaledGameResource
  include BaseResource

  attribute :game do |game|
    GameSummaryResource.new(game).serializable_hash
  end

  attribute :entry_count do |game|
    game["entry_count"]
  end

  attribute :last_entry_at do |game|
    game["last_entry_at"]
  end
end
