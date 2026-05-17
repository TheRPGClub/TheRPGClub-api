# frozen_string_literal: true

class CreateRpgClubUsers < ActiveRecord::Migration[8.1]
  def up
    return if table_exists?(:rpg_club_users)

    create_table :rpg_club_users, id: false do |table|
      table.string :user_id, limit: 30, null: false
      table.boolean :is_bot, default: false, null: false
      table.string :username, limit: 100
      table.string :global_name, limit: 100
      table.binary :avatar_blob
      table.datetime :server_joined_at, precision: 6
      table.datetime :last_seen_at, precision: 6
      table.datetime :last_fetched_at, precision: 6
      table.boolean :role_admin, default: false, null: false
      table.boolean :role_moderator, default: false, null: false
      table.boolean :role_regular, default: false, null: false
      table.boolean :role_member, default: false, null: false
      table.boolean :role_newcomer, default: false, null: false
      table.datetime :created_at, precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
      table.datetime :updated_at, precision: 6, default: -> { "CURRENT_TIMESTAMP" }, null: false
      table.datetime :server_left_at, precision: 6
      table.integer :message_count, default: 0
      table.binary :profile_image
      table.datetime :profile_image_at, precision: 6
      table.boolean :donor_notify_on_claim, default: false, null: false
    end

    execute "ALTER TABLE rpg_club_users ADD PRIMARY KEY (user_id)"
  end

  def down
    drop_table :rpg_club_users, if_exists: true
  end
end
