# frozen_string_literal: true

# Secret Santa: Editions, sign-up and the draw (GLOSSARY.md, "Assignment",
# "Edition"; spec #376, ticket #383).
#
# An Assignment Challenge keeps its Edition calendar on `challenges`: the
# sign-up cutoff, the pick deadline and the reveal date, each a month and day.
#
# challenge_editions holds each yearly Edition with its concrete dates (club
# time zone) and its phase. An Edition is named by the year of its reveal and
# ends on the next reveal date, one year later.
#
# challenge_edition_signups holds the members signed up for an Edition: one
# row each, `left_out_at` when the draw left them out (fewer than 5 games in
# their backlog), and `recipient_user_id`, the member they give to, once
# drawn. Ticket #384 adds the pick.
#
# A drawn member's Run belongs to the Edition (`challenge_runs.edition_id`).
# Editions overlap (the next one signs up while the last one's year to Clear
# runs), so the one-Active-Run rule applies to Runs outside an Edition, and
# an Edition has at most one Run per member.
class CreateChallengeEditions < ActiveRecord::Migration[8.1]
  def change
    change_table :challenges, bulk: true do |t|
      t.integer :signup_cutoff_month, limit: 2
      t.integer :signup_cutoff_day, limit: 2
      t.integer :pick_deadline_month, limit: 2
      t.integer :pick_deadline_day, limit: 2
      t.integer :reveal_month, limit: 2
      t.integer :reveal_day, limit: 2
      t.check_constraint "challenge_format <> 'assignment' OR (schedule = 'always_open' AND ends_on IS NULL)",
        name: "ck_challenges_assignment_schedule"
    end

    create_table :challenge_editions do |t|
      t.bigint :challenge_id, null: false
      t.integer :year, null: false
      t.string :phase, limit: 16, null: false, default: "signup"
      t.date :signup_opens_on, null: false
      t.date :signup_cutoff_on, null: false
      t.date :pick_deadline_on, null: false
      t.date :reveal_on, null: false
      t.date :ends_on, null: false
      t.timestamptz :drawn_at
      t.timestamps

      t.check_constraint "phase IN ('signup', 'picking', 'revealed', 'ended', 'cancelled')",
        name: "ck_challenge_editions_phase"
      t.check_constraint "signup_opens_on < signup_cutoff_on AND signup_cutoff_on < pick_deadline_on AND " \
                         "pick_deadline_on < reveal_on AND reveal_on < ends_on",
        name: "ck_challenge_editions_dates"
    end
    add_index :challenge_editions, %i[challenge_id year], unique: true, name: "ux_challenge_editions_year"
    add_index :challenge_editions, %i[phase signup_cutoff_on], name: "ix_challenge_editions_phase"
    add_foreign_key :challenge_editions, :challenges, on_delete: :cascade, name: "fk_challenge_editions_challenge"

    create_table :challenge_edition_signups do |t|
      t.bigint :edition_id, null: false
      t.string :user_id, limit: 30, null: false
      t.timestamptz :signed_up_at, null: false, default: -> { "statement_timestamp()" }
      t.timestamptz :left_out_at
      t.string :recipient_user_id, limit: 30
      t.timestamps
    end
    add_index :challenge_edition_signups, %i[edition_id user_id], unique: true, name: "ux_challenge_edition_signups_member"
    add_index :challenge_edition_signups, %i[edition_id recipient_user_id], unique: true,
      where: "recipient_user_id IS NOT NULL", name: "ux_challenge_edition_signups_recipient"
    add_index :challenge_edition_signups, :user_id, name: "ix_challenge_edition_signups_user"
    add_foreign_key :challenge_edition_signups, :challenge_editions, column: :edition_id, on_delete: :cascade,
      name: "fk_challenge_edition_signups_edition"
    add_foreign_key :challenge_edition_signups, :rpg_club_users, column: :user_id, primary_key: :user_id,
      on_delete: :cascade, name: "fk_challenge_edition_signups_user"
    add_foreign_key :challenge_edition_signups, :rpg_club_users, column: :recipient_user_id, primary_key: :user_id,
      on_delete: :nullify, name: "fk_challenge_edition_signups_recipient"

    add_column :challenge_runs, :edition_id, :bigint
    add_foreign_key :challenge_runs, :challenge_editions, column: :edition_id, on_delete: :cascade,
      name: "fk_challenge_runs_edition"
    add_index :challenge_runs, %i[edition_id user_id], unique: true, where: "edition_id IS NOT NULL",
      name: "ux_challenge_runs_edition_member"
    remove_index :challenge_runs, %i[challenge_id user_id], unique: true, where: "status = 'active'",
      name: "ux_challenge_runs_one_active"
    add_index :challenge_runs, %i[challenge_id user_id], unique: true,
      where: "status = 'active' AND edition_id IS NULL", name: "ux_challenge_runs_one_active"
  end
end
