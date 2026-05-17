# frozen_string_literal: true

class UserSocial < ApplicationRecord
  self.table_name = "user_socials"

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    optional: true,
    inverse_of: :socials

  belongs_to :social_platform,
    foreign_key: :platform_id,
    inverse_of: :user_socials

  validates :user_id, :display_text, presence: true
  validates :display_text, uniqueness: { scope: %i[user_id platform_id] }
end
