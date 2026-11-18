# frozen_string_literal: true

# The Challenges lifecycle job (spec #376, "Lifecycle job"; ticket #379).
#
# challenge_lifecycle_steps records each timed step the job has taken for a
# Challenge, by the club date it was due on: one row per (Challenge, step,
# date), so a repeated or late tick never takes it again (a Season opened
# announcement, a Season ending reminder; the Edition steps of #383/#384
# record theirs the same way).
#
# `challenges.ended_at` is when an Always Open Challenge reached its end date
# and Closed for good. `rpg_club_users.challenge_dms` is the member's Challenge
# DM opt-out, next to their other notification preference.
class CreateChallengeLifecycleSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :challenge_lifecycle_steps do |t|
      t.bigint :challenge_id, null: false
      t.string :step, limit: 48, null: false
      t.date :occurs_on, null: false
      t.timestamptz :done_at, null: false, default: -> { "statement_timestamp()" }
    end
    add_index :challenge_lifecycle_steps, %i[challenge_id step occurs_on], unique: true,
      name: "ux_challenge_lifecycle_steps_once"
    add_foreign_key :challenge_lifecycle_steps, :challenges, on_delete: :cascade,
      name: "fk_challenge_lifecycle_steps_challenge"

    add_column :challenges, :ended_at, :timestamptz,
      comment: "When the Always Open Challenge reached its end date and Closed for good."
    add_column :rpg_club_users, :challenge_dms, :boolean, null: false, default: true,
      comment: "Whether the member wants Challenge reminder DMs (on by default)."
  end
end
