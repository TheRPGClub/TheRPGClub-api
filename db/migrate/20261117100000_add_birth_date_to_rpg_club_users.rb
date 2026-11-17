# frozen_string_literal: true

# Challenges (spec #376, ticket #380): the member's Birth Date, and each time
# it was set or changed. A member may set or change it at most twice per
# calendar month in the club's time zone, first entry included; the times
# staff changed it are kept too, flagged, and don't count.
class AddBirthDateToRpgClubUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :rpg_club_users, :birth_date, :date,
      comment: "The member's Birth Date. Only the member and staff see the full date."

    create_table :member_birth_date_changes do |t|
      t.string :user_id, limit: 30, null: false
      t.date :birth_date, comment: "The Birth Date it was set to (null when removed)."
      t.string :changed_by, limit: 30, comment: "Discord user id of whoever changed it; null for the bot."
      t.boolean :by_staff, null: false, default: false,
        comment: "Changed by staff, which doesn't count toward the member's limit."
      t.datetime :changed_at, null: false
    end

    add_index :member_birth_date_changes, %i[user_id changed_at]
    add_foreign_key :member_birth_date_changes, :rpg_club_users, column: :user_id, primary_key: :user_id,
      on_delete: :cascade
  end
end
