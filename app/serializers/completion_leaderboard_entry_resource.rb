# frozen_string_literal: true

# A single row of the completions leaderboard (CompletionsController#leaderboard):
# a user's identity plus their total `completion_count`. Not a plain model
# record — the controller hands in the grouped/aggregated rows (the user
# identity columns selected off `rpg_club_users` plus the `COUNT(*)`
# `completion_count` alias), so this reads those selected attributes the same
# way JournaledGameResource serializes its grouped aggregates.
class CompletionLeaderboardEntryResource
  include BaseResource

  attributes :user_id, :username, :global_name

  attribute :completion_count do |row|
    row["completion_count"].to_i
  end
end
