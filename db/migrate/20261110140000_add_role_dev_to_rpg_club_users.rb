# frozen_string_literal: true

# Stores the dev role (Superadmin) on the member, kept current by sign-in and
# the bot's role reports like the other role flags, so the API can tell
# whether a Discord user acting through the bot is a Superadmin (spec #347).
class AddRoleDevToRpgClubUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :rpg_club_users, :role_dev, :boolean, default: false, null: false
  end
end
