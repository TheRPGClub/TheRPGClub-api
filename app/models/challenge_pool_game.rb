# frozen_string_literal: true

# A game a person put in a Pool Challenge as a Core or Optional Game, or
# excluded from its sources, and when (`added_at`, for "new";
# Challenges::PoolDefinition).
class ChallengePoolGame < ApplicationRecord
  INCLUSIONS = %w[core optional exclude].freeze

  self.primary_key = %i[challenge_id game_id]

  belongs_to :challenge, inverse_of: :pool_games
  belongs_to :game, class_name: "GamedbGame", foreign_key: :game_id, inverse_of: false

  validates :inclusion, inclusion: { in: INCLUSIONS }
end
