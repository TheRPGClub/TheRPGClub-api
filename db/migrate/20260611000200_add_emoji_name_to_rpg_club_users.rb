# frozen_string_literal: true

class AddEmojiNameToRpgClubUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :rpg_club_users, :emoji_name, :string, limit: 32
  end
end
