# frozen_string_literal: true

class UserGameCompletion < ApplicationRecord
  self.table_name = "user_game_completions"
  self.primary_key = "completion_id"

  # Run progress follows every commit (Challenges::CountsTowardRuns).
  include Challenges::CountsTowardRuns

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    optional: true,
    inverse_of: :game_completions
  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    inverse_of: :user_game_completions
  belongs_to :platform,
    class_name: "GamedbPlatform",
    foreign_key: :platform_id,
    optional: true,
    inverse_of: :user_game_completions

  validates :user_id, :gamedb_game_id, :completion_type, presence: true
end
