# frozen_string_literal: true

class RpgClubUserAvatarHistory < ApplicationRecord
  self.table_name = "rpg_club_user_avatar_history"
  self.primary_key = "event_id"

  belongs_to :user, -> { without_images }, class_name: "RpgClubUser", foreign_key: :user_id, primary_key: :user_id
end
