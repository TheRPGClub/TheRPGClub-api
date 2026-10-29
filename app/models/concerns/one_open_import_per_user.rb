# frozen_string_literal: true

# One active or paused import per user per import kind (web-parity #287).
# Included by the Steam, collection CSV and Completionator import models, so
# both the bot's create endpoints and the web workflows get the same rule:
# a create (or a reopen of a completed/canceled import) fails validation
# with "user already has an active or paused import" while the user has
# another open import of that kind, which the controllers render as 422.
#
# The check takes a transaction-scoped advisory lock on (table, user_id) so
# two concurrent creates can't both pass. Moving an open import between
# active and paused is never re-checked, so legacy users who already have
# two open imports (from before this rule) can still pause, resume and
# finish them.
#
#   RpgClubSteamCollectionImport.open_for_user(user_id) # active or paused imports
module OneOpenImportPerUser
  extend ActiveSupport::Concern

  OPEN_STATUSES = %w[active paused].freeze
  ERROR_MESSAGE = "user already has an active or paused import"

  included do
    scope :open_for_user, ->(user_id) { where(user_id: user_id, status: OPEN_STATUSES) }

    validate :only_one_open_import_per_user, if: :opening?
  end

  private

  def opening?
    return false unless OPEN_STATUSES.include?(status)

    new_record? || (will_save_change_to_status? && OPEN_STATUSES.exclude?(status_in_database))
  end

  def only_one_open_import_per_user
    lock_user_imports!
    others = self.class.open_for_user(user_id)
    others = others.where.not(self.class.primary_key => id) if persisted?
    errors.add(:base, ERROR_MESSAGE) if others.exists?
  end

  # Only meaningful inside the save transaction (validations run in it); a
  # bare #valid? call outside one just releases the lock immediately.
  def lock_user_imports!
    key = "#{self.class.table_name}:#{user_id}"
    self.class.connection.execute(
      self.class.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(hashtext(?))", key ])
    )
  end
end
