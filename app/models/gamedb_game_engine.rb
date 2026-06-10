# frozen_string_literal: true

class GamedbGameEngine < ApplicationRecord
  self.table_name = "gamedb_game_engines"
  self.primary_key = %i[game_id engine_id]

  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :game_id,
    inverse_of: :game_engines
  belongs_to :engine,
    class_name: "GamedbEngine",
    foreign_key: :engine_id,
    inverse_of: :game_engines
end
