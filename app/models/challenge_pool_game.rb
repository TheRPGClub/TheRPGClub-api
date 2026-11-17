# frozen_string_literal: true

# A game a Pool Challenge's Host included in, or excluded from, the Pool by
# hand (Challenges::PoolDefinition).
class ChallengePoolGame < ApplicationRecord
  INCLUSIONS = %w[include exclude].freeze

  self.primary_key = %i[challenge_id game_id]

  belongs_to :challenge, inverse_of: :pool_games
  belongs_to :game, class_name: "GamedbGame", foreign_key: :game_id, inverse_of: false

  validates :inclusion, inclusion: { in: INCLUSIONS }
end
