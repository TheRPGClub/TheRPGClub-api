# frozen_string_literal: true

# The channel counts API was removed (#90) -- it was dead code, never called
# by the Discord bot. This drops the now-unused rpg_club_user_channel_counts
# table.
class DropRpgClubUserChannelCounts < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:rpg_club_user_channel_counts)

    drop_table :rpg_club_user_channel_counts
  end

  def down
    create_table :rpg_club_user_channel_counts, primary_key: %i[user_id channel_id] do |table|
      table.string :user_id, limit: 30, null: false
      table.string :channel_id, limit: 30, null: false
      table.bigint :message_count, default: 0, null: false
      table.datetime :last_scanned_at, precision: 6
      table.datetime :created_at, precision: 6, default: -> { "statement_timestamp()" }, null: false
      table.datetime :updated_at, precision: 6, default: -> { "statement_timestamp()" }, null: false
    end
  end
end
