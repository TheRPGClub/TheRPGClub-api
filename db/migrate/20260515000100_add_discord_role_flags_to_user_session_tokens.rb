# frozen_string_literal: true

class AddDiscordRoleFlagsToUserSessionTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :user_session_tokens, :is_dev, :boolean, default: false, null: false
    add_column :user_session_tokens, :is_longstanding, :boolean, default: false, null: false
  end
end
