# frozen_string_literal: true

# A member's proposal for the bot or website. Kept after review with a status
# (web parity 2, #318): pending until a Superadmin approves it into a GitHub
# issue or rejects it with a reason, or its author withdraws it.
class RpgClubSuggestion < ApplicationRecord
  self.table_name = "rpg_club_suggestions"
  self.primary_key = "suggestion_id"

  STATUSES = %w[pending approved rejected withdrawn].freeze

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
end
