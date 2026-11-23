# frozen_string_literal: true

# A game in the Review Feed and the drafts listing: GameResource (with the
# `gotm_won` / `nr_gotm_won` flags) plus the month each track was won
# (`gotm_month_year` / `nr_gotm_month_year`, as games#show serves them), so
# a track pill reads "GOTM · Nov 2024". Only for games loaded through
# `GamedbGame.without_images.with_track_months` (UserGameReview#tracked_game).
class TrackedGameResource
  include BaseResource
  include GameFields

  attributes :gotm_won, :nr_gotm_won, :gotm_month_year, :nr_gotm_month_year
end
