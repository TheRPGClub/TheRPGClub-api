# frozen_string_literal: true

class UserReminder < ApplicationRecord
  self.table_name = "user_reminders"
  self.primary_key = "reminder_id"

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    optional: true,
    inverse_of: :reminders

  validates :user_id, :remind_at, :content, presence: true
end
