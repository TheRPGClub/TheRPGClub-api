# frozen_string_literal: true

# Live events (web parity 2, #336): a Moderator creates one on the site and
# the bot's `live_event_create` job makes the forum thread and the Discord
# scheduled event, recording each id here as it is made.
class CreateLiveEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :live_events do |t|
      t.string :topic, limit: 100, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.text :image_url
      t.string :status, limit: 16, null: false, default: "queued"
      t.string :discord_thread_id, limit: 30
      t.string :discord_event_id, limit: 30
      t.string :created_by_user_id, limit: 30
      t.timestamps
    end

    add_index :live_events, :created_at
    add_foreign_key :live_events, :rpg_club_users, column: :created_by_user_id, primary_key: :user_id,
      on_delete: :nullify
    add_check_constraint :live_events, "status IN ('queued', 'thread_created', 'created', 'failed')",
      name: "ck_live_events_status"
    add_check_constraint :live_events, "ends_at > starts_at", name: "ck_live_events_ends_after_start"
  end
end
