# frozen_string_literal: true

class GamedbReleaseAnnouncement < ApplicationRecord
  self.table_name = "gamedb_release_announcements"
  self.primary_key = "release_id"

  belongs_to :release,
    class_name: "GamedbRelease",
    foreign_key: :release_id,
    inverse_of: :announcement

  validates :announce_at, presence: true
end
