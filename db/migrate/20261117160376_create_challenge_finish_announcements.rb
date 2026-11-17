# frozen_string_literal: true

# A member's Finish of a Seasonal Challenge is announced at most once per
# Season (spec #376, "Bot jobs"). One Run per member per Season is the rule
# (Challenges::Runs.start!), but a member may delete a Finished Run and start
# again in the same Season, and the new Run may Finish at once on the
# Season's earlier play. Like `challenge_runs.caught_up_announced_year` for
# Caught Up, this records what was announced, here outside the Run so a
# deleted Run doesn't take it along: one row per (Challenge, member, Season).
# Always Open Runs are not recorded.
class CreateChallengeFinishAnnouncements < ActiveRecord::Migration[8.1]
  def change
    create_table :challenge_finish_announcements, primary_key: %i[challenge_id user_id season_starts_on] do |t|
      t.bigint :challenge_id, null: false
      t.string :user_id, limit: 30, null: false
      t.date :season_starts_on, null: false
      t.timestamptz :announced_at, null: false, default: -> { "statement_timestamp()" }
    end
    add_foreign_key :challenge_finish_announcements, :challenges, on_delete: :cascade,
      name: "fk_challenge_finish_announcements_challenge"
    add_foreign_key :challenge_finish_announcements, :rpg_club_users, column: :user_id, primary_key: :user_id,
      on_delete: :cascade, name: "fk_challenge_finish_announcements_user"
  end
end
