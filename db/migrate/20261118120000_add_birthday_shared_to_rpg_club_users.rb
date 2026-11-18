# frozen_string_literal: true

# Birthdays (api#399): a member chooses whether their Birthday, the day and
# month of their Birth Date, is shared. Off for everyone, including every
# existing Birth Date. Only a member with a Birth Date can share a Birthday.
class AddBirthdaySharedToRpgClubUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :rpg_club_users, :birthday_shared, :boolean, null: false, default: false,
      comment: "Whether the member shares their Birthday (the day and month of their Birth Date, never the year). " \
               "Only the member turns it on; staff can turn it off; removing the Birth Date turns it off."
    add_check_constraint :rpg_club_users, "NOT birthday_shared OR birth_month IS NOT NULL",
      name: "ck_rpg_club_users_birthday_shared"
  end
end
