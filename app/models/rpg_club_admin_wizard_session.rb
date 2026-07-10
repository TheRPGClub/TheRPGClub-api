# frozen_string_literal: true

class RpgClubAdminWizardSession < ApplicationRecord
  self.table_name = "rpg_club_admin_wizard_sessions"
  self.primary_key = "session_id"

  STATUSES = %w[active completed cancelled].freeze

  before_validation :assign_session_id, on: :create

  validates :session_id, :command_key, :owner_user_id, :channel_id, :state_json, presence: true
  validates :status, inclusion: { in: STATUSES }

  private

  def assign_session_id
    self.session_id ||= SecureRandom.hex(16)
  end
end
