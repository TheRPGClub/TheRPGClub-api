# frozen_string_literal: true

# The bot job queue (web parity 2): work the API asks the bot to do in
# Discord. Separate from voting_events, which stays as is.
class CreateBotJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :bot_jobs do |t|
      t.string :kind, limit: 64, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :status, limit: 16, null: false, default: "queued"
      t.string :requested_by_user_id, limit: 30
      t.datetime :claimed_at
      t.integer :attempts, null: false, default: 0
      t.text :error_message
      t.datetime :finished_at
      t.timestamps
    end

    add_index :bot_jobs, :id, where: "status = 'queued'", name: "ix_bot_jobs_queued"
    add_index :bot_jobs, :claimed_at, where: "status = 'claimed'", name: "ix_bot_jobs_claimed"
    add_index :bot_jobs, :requested_by_user_id
    add_foreign_key :bot_jobs, :rpg_club_users, column: :requested_by_user_id, primary_key: :user_id,
      on_delete: :nullify
    add_check_constraint :bot_jobs, "status IN ('queued', 'claimed', 'done', 'failed')", name: "ck_bot_jobs_status"
  end
end
