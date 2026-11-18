# frozen_string_literal: true

# A GameDB collection chosen for a Pool Challenge: its games are in the Pool
# unless excluded by hand (Challenges::PoolDefinition).
class ChallengePoolCollection < ApplicationRecord
  self.primary_key = %i[challenge_id collection_id]

  belongs_to :challenge, inverse_of: :pool_collections
  belongs_to :collection, class_name: "GamedbCollection", foreign_key: :collection_id, inverse_of: false
end
