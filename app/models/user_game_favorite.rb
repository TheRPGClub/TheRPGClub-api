# frozen_string_literal: true

class UserGameFavorite < ApplicationRecord
  self.table_name = "user_game_favorites"
  self.primary_key = "entry_id"

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    inverse_of: :game_favorites
  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    inverse_of: :user_favorites

  validates :user_id, :gamedb_game_id, presence: true
  validates :user_id, uniqueness: { scope: :gamedb_game_id }
end
