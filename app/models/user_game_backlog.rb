# frozen_string_literal: true

class UserGameBacklog < ApplicationRecord
  self.table_name = "user_game_backlog"
  self.primary_key = "entry_id"

  include ShelfOrder

  # The list's display order (BacklogController#index, ShelfOrder).
  SHELF_ORDER = { sort_order: :asc, created_at: :desc, entry_id: :desc }.freeze

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    inverse_of: :game_backlog_entries
  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    inverse_of: :user_backlog_entries
  belongs_to :platform,
    class_name: "GamedbPlatform",
    foreign_key: :platform_id,
    optional: true,
    inverse_of: :user_backlog_entries

  validates :user_id, :gamedb_game_id, presence: true
end
