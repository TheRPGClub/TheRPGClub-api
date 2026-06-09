# frozen_string_literal: true

class UserGameJournalEntry < ApplicationRecord
  self.table_name = "user_game_journal_entries"
  self.primary_key = "entry_id"

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    inverse_of: :journal_entries
  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    inverse_of: :journal_entries

  validates :user_id, :gamedb_game_id, presence: true
  validates :entry_body, presence: true

  # The games a user has journaled — one row per game, each carrying the
  # `entry_count` and `last_entry_at` aggregates. Callers add their own ORDER
  # (title for the grid, recency for the profile preview). Shared by
  # journal#index and the UserResource profile preview.
  def self.journaled_games_for(user_id)
    GamedbGame
      .joins("INNER JOIN user_game_journal_entries je ON je.gamedb_game_id = gamedb_games.game_id")
      .where("je.user_id = ?", user_id)
      .group("gamedb_games.game_id")
      .select("gamedb_games.*, COUNT(*) AS entry_count, MAX(je.created_at) AS last_entry_at")
      .preload(:images)
  end
end
