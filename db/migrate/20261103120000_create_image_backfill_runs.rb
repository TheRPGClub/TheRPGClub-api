# frozen_string_literal: true

# Progress of the image backfill (web parity 2, #338): the API's
# Gamedb::ImageBackfillJob, which replaces the bot's
# `/superadmin download-missing-images`. The partial unique index keeps at
# most one run queued or running.
class CreateImageBackfillRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :image_backfill_runs do |t|
      t.string :status, limit: 16, null: false, default: "queued"
      t.integer :total, null: false, default: 0
      t.integer :done, null: false, default: 0
      t.integer :skipped, null: false, default: 0
      t.integer :failed, null: false, default: 0
      t.string :started_by_user_id, limit: 30
      t.datetime :started_at
      t.datetime :finished_at
      t.text :last_error
      t.timestamps
    end

    add_index :image_backfill_runs, :status, unique: true, where: "status IN ('queued', 'running')",
      name: "ix_image_backfill_runs_one_in_progress"
    add_foreign_key :image_backfill_runs, :rpg_club_users, column: :started_by_user_id, primary_key: :user_id,
      on_delete: :nullify
    add_check_constraint :image_backfill_runs, "status IN ('queued', 'running', 'completed', 'failed')",
      name: "ck_image_backfill_runs_status"
  end
end
