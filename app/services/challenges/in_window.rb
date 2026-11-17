# frozen_string_literal: true

module Challenges
  # A member's plays inside one Run's window: `cleared` by game id, and the
  # ids of the games `in_progress`.
  InWindow = Data.define(:cleared, :in_progress) do
    def game_ids = cleared.keys | in_progress

    # The game counted as it stands: Cleared, In Progress, or nil.
    def counted(game_id) = cleared[game_id] || (Counted.in_progress(game_id) if in_progress.include?(game_id))
  end
end
