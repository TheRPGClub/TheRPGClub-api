# frozen_string_literal: true

# A GameDB franchise chosen for a Pool Challenge: its games are in the Pool
# unless excluded by hand (Challenges::PoolDefinition).
class ChallengePoolFranchise < ApplicationRecord
  self.primary_key = %i[challenge_id franchise_id]

  belongs_to :challenge, inverse_of: :pool_franchises
  belongs_to :franchise, class_name: "GamedbFranchise", foreign_key: :franchise_id, inverse_of: false
end
