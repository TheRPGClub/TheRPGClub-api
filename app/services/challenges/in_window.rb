# frozen_string_literal: true

module Challenges
  # A member's plays inside one Run's window: `cleared` by game id, and the
  # ids of the games `in_progress`. `earlier` holds their Game Completions
  # dated before the window or undated, by completion id, which count only
  # when the member picks them by hand (Counts past play).
  InWindow = Data.define(:cleared, :in_progress, :earlier) do
    def initialize(earlier: {}, **) = super

    def game_ids = cleared.keys | in_progress

    # The game counted as it stands: Cleared, In Progress, or nil.
    def counted(game_id) = cleared[game_id] || (Counted.in_progress(game_id) if in_progress.include?(game_id))
  end
end
