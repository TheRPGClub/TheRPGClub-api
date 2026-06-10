# frozen_string_literal: true

class GamedbEngine < ApplicationRecord
  self.table_name = "gamedb_engines"
  self.primary_key = "engine_id"

  has_many :game_engines,
    class_name: "GamedbGameEngine",
    foreign_key: :engine_id,
    dependent: nil,
    inverse_of: :engine
  has_many :games,
    through: :game_engines,
    source: :game

  validates :name, presence: true
end
