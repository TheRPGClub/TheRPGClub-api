# frozen_string_literal: true

# A member's cached progress on one Achievement Set, so reads never aggregate
# over every Unlock. A row with `synced_at` nil is a placeholder waiting for its
# first import and is excluded from every read; `sync_pending_at` marks a set
# waiting for an import (ADR 0003).
class UserAchievementSetProgress < ApplicationRecord
  self.table_name = "user_achievement_set_progress"

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    inverse_of: :achievement_set_progress
  belongs_to :achievement_set, inverse_of: :progress
  belongs_to :linked_account,
    class_name: "UserLinkedAccount",
    foreign_key: :user_linked_account_id,
    inverse_of: :set_progress

  validates :achievement_set_id, uniqueness: { scope: :user_id }
end
