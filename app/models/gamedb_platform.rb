# frozen_string_literal: true

class GamedbPlatform < ApplicationRecord
  self.table_name = "gamedb_platforms"
  self.primary_key = "platform_id"

  has_many :releases,
    class_name: "GamedbRelease",
    foreign_key: :platform_id,
    dependent: nil,
    inverse_of: :platform
  has_many :game_platforms,
    class_name: "GamedbGamePlatform",
    foreign_key: :platform_id,
    dependent: nil,
    inverse_of: :platform
  has_many :games,
    through: :game_platforms,
    source: :game
  has_many :user_game_collections,
    class_name: "UserGameCollection",
    foreign_key: :platform_id,
    dependent: nil,
    inverse_of: :platform
  has_many :user_game_completions,
    class_name: "UserGameCompletion",
    foreign_key: :platform_id,
    dependent: nil,
    inverse_of: :platform
  has_many :user_backlog_entries,
    class_name: "UserGameBacklog",
    foreign_key: :platform_id,
    dependent: nil,
    inverse_of: :platform

  validates :platform_code, :platform_name, presence: true
end
