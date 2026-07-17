# frozen_string_literal: true

# A single row within a RpgClubCompletionatorImport (#164). Carries the raw
# parsed Completionator export values alongside the resolved match once the
# bot's matcher has run (`gamedb_game_id`), and the outcome
# (`status`/`completion_id`/`error_text`).
class RpgClubCompletionatorImportItem < ApplicationRecord
  self.table_name = "rpg_club_completionator_import_items"
  self.primary_key = "item_id"

  STATUSES = %w[pending added updated skipped failed].freeze

  belongs_to :import,
    class_name: "RpgClubCompletionatorImport",
    foreign_key: :import_id,
    primary_key: :import_id,
    inverse_of: :items

  validates :import_id, :row_index, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :row_index, uniqueness: { scope: :import_id }
end
