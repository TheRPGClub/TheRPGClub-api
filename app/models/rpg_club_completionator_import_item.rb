# frozen_string_literal: true

# A single row within a RpgClubCompletionatorImport (#164). Carries the raw
# parsed Completionator export values alongside the resolved match once the
# bot's matcher has run (`gamedb_game_id`), and the outcome
# (`status`/`completion_id`/`error_text`).
class RpgClubCompletionatorImportItem < ApplicationRecord
  self.table_name = "rpg_club_completionator_import_items"
  self.primary_key = "item_id"

  STATUSES = %w[pending added updated skipped failed].freeze
  # The bot writes `imported`/`error` (and upper-cases statuses), which the
  # API never accepted, so those writes used to 422. They are normalised to
  # the canonical values instead, so the bot keeps working unchanged.
  LEGACY_STATUSES = { "imported" => "added", "error" => "failed" }.freeze

  before_validation :normalize_status

  belongs_to :import,
    class_name: "RpgClubCompletionatorImport",
    foreign_key: :import_id,
    primary_key: :import_id,
    inverse_of: :items

  validates :import_id, :row_index, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :row_index, uniqueness: { scope: :import_id }

  private

  def normalize_status
    return if status.nil?

    value = status.to_s.strip.downcase
    value = LEGACY_STATUSES.fetch(value, value)
    self.status = value if STATUSES.include?(value)
  end
end
