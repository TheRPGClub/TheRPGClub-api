# frozen_string_literal: true

# A game counted on a Run (spec #376, "Run entries"): In Progress while it is
# in the member's Now Playing, Cleared by the Game Completion `completion_id`
# dated `cleared_on` inside the Run's window. On a Slots Run a Cleared game
# fills the slot of `slot_year` (null while it waits for an open year), and
# `picked_by_hand` marks a game the member moved there. Written only by
# Challenges::Progress and a slot move (Challenges::Runs.move!).
class ChallengeRunEntry < ApplicationRecord
  STATES = %w[in_progress cleared].freeze

  belongs_to :run, class_name: "ChallengeRun", inverse_of: :entries
  belongs_to :game, class_name: "GamedbGame", primary_key: :game_id, inverse_of: false

  validates :state, inclusion: { in: STATES }

  def cleared? = state == "cleared"
end
