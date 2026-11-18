# frozen_string_literal: true

# The Birthday Post (spec #396, ticket #401). birthday_posts records each
# member greeted, by calendar year: one row per member and year
# (ux_birthday_posts_once), written when the post is queued, so a member gets
# at most one Birthday Post a year however their Birth Date changes, and a
# re-run of the job the same day queues nothing new.
class CreateBirthdayPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :birthday_posts, comment: "Each member's Birthday Post, at most one per calendar year." do |t|
      t.string :user_id, limit: 30, null: false
      t.integer :year, limit: 2, null: false, comment: "The calendar year of the club day it was queued for."
      t.date :posted_on, null: false, comment: "The club day (America/New_York) it was queued for."
      t.timestamptz :created_at, null: false, default: -> { "statement_timestamp()" }
    end
    add_index :birthday_posts, %i[user_id year], unique: true, name: "ux_birthday_posts_once"
    add_foreign_key :birthday_posts, :rpg_club_users, column: :user_id, primary_key: :user_id,
      on_delete: :cascade, name: "fk_birthday_posts_user"
  end
end
