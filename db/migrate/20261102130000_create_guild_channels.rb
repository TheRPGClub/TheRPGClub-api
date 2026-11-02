# frozen_string_literal: true

# The guild's Discord channels as the bot last reported them (web parity 2,
# #313), so the website can offer channel pickers. Keyed on the Discord
# snowflake. `channel_type` is Discord's numeric ChannelType; categories are
# stored too so text channels can be grouped and ordered by their category.
class CreateGuildChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :guild_channels, id: false do |t|
      t.string :channel_id, null: false, primary_key: true
      t.string :name, null: false
      t.integer :channel_type, null: false
      t.string :parent_id
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :guild_channels, %i[channel_type parent_id position], name: "ix_guild_channels_type_parent_position"
  end
end
