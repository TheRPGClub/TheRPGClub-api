# frozen_string_literal: true

class UserGameCollection < ApplicationRecord
  self.table_name = "user_game_collections"
  self.primary_key = "entry_id"

  belongs_to :user, -> { without_images },
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    optional: true,
    inverse_of: :game_collections
  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    inverse_of: :user_game_collections
  belongs_to :platform,
    class_name: "GamedbPlatform",
    foreign_key: :platform_id,
    optional: true,
    inverse_of: :user_game_collections

  validates :user_id, :gamedb_game_id, :ownership_type, presence: true
end
