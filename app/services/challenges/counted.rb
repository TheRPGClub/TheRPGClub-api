# frozen_string_literal: true

module Challenges
  # A game counted on a Run, before it is written as a ChallengeRunEntry.
  Counted = Data.define(:game_id, :state, :completion_id, :cleared_on) do
    def self.cleared(game_id, completion_id, date) = new(game_id:, state: "cleared", completion_id:, cleared_on: date)

    def self.in_progress(game_id) = new(game_id:, state: "in_progress", completion_id: nil, cleared_on: nil)

    def cleared? = state == "cleared"
  end
end
