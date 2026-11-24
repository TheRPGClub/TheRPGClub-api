# frozen_string_literal: true

# Game Completion `completed_at` is a day (spec api#451, the day rule) and is
# now written as noon club time (America/New_York) of that day. Existing rows
# were stored at midnight UTC (or as the bot's full "now"), and members read
# them as their UTC date (the export, the website, Challenges). Move each to
# noon club time of its current UTC date: same UTC date, and now the same club
# day too, so every reader agrees without a legacy branch.
class StoreCompletionDaysAtClubNoon < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE user_game_completions
      SET completed_at = ((completed_at::date + TIME '12:00') AT TIME ZONE 'America/New_York') AT TIME ZONE 'UTC'
      WHERE completed_at IS NOT NULL
    SQL
  end

  # Back to midnight UTC of the same day (a full "now" a row once held is not
  # restored; its day is).
  def down
    execute <<~SQL.squish
      UPDATE user_game_completions SET completed_at = completed_at::date WHERE completed_at IS NOT NULL
    SQL
  end
end
