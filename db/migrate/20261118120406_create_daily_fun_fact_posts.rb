# frozen_string_literal: true

# The Daily Fun Fact (spec #397, ticket #406). daily_fun_fact_posts records
# the Fun Fact queued for each club day: one row per club date
# (ux_daily_fun_fact_posts_club_date), written with the bot job, so a re-run
# of the job the same day posts nothing new.
class CreateDailyFunFactPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :daily_fun_fact_posts, comment: "The Fun Fact queued as each club day's Daily Fun Fact." do |t|
      t.date :club_date, null: false, comment: "The club day (America/New_York) it was queued for."
      t.bigint :entry_id, comment: "The Fun Fact posted; null once it is deleted, so the day stays posted."
      t.timestamptz :created_at, null: false, default: -> { "statement_timestamp()" }
    end
    add_index :daily_fun_fact_posts, :club_date, unique: true, name: "ux_daily_fun_fact_posts_club_date"
    add_index :daily_fun_fact_posts, :entry_id, name: "ix_daily_fun_fact_posts_entry"
    add_foreign_key :daily_fun_fact_posts, :codex_entries, column: :entry_id,
      on_delete: :nullify, name: "fk_daily_fun_fact_posts_entry"
  end
end
