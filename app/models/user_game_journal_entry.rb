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
end
