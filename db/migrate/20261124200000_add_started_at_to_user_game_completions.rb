# frozen_string_literal: true

# The day a member started the game a Game Completion records (spec api#451),
# so a completion reads as a play log ("started 9 Nov, finished 24 Nov").
# Optional: existing rows keep it null.
class AddStartedAtToUserGameCompletions < ActiveRecord::Migration[8.1]
  def change
    add_column :user_game_completions, :started_at, :date
  end
end
