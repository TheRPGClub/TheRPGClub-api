# frozen_string_literal: true

module Challenges
  # A game counted on a Run, before it is written as a ChallengeRunEntry.
  # A Slots Run's Cleared game may fill the slot of `slot_year`, and
  # `picked_by_hand` marks one the member placed there themselves.
  Counted = Data.define(:game_id, :state, :completion_id, :cleared_on, :slot_year, :picked_by_hand) do
    def initialize(slot_year: nil, picked_by_hand: false, **) = super

    def self.cleared(game_id, completion_id, date) = new(game_id:, state: "cleared", completion_id:, cleared_on: date)

    def self.in_progress(game_id) = new(game_id:, state: "in_progress", completion_id: nil, cleared_on: nil)

    def cleared? = state == "cleared"
  end
end
