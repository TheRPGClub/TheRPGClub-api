# frozen_string_literal: true

# A Linked Account: a member's identity on one Provider, claimed by the member
# and used to sync their achievements. `external_id` is the Provider's stable
# id (RA ULID, SteamID64 or PSN accountId), never a renameable name. One member
# per Provider identity, and one Linked Account per member per Provider.
#
# Sync state is durable here (ADR 0003): `sync_due_at` marks an account waiting
# for a listing. Unlinking (destroy) deletes the account's Unlocks and progress
# through the database cascades; the shared definitions stay.
class UserLinkedAccount < ApplicationRecord
  PROVIDERS = %w[retroachievements steam psn].freeze
  SYNC_STATUSES = %w[pending ok private not_found error].freeze
  SYNC_MODES = %w[backfill incremental].freeze
  # How long after a Sync now the member must wait before the next one.
  SYNC_COOLDOWN = 15.minutes

  enum :provider, PROVIDERS.index_with(&:itself), validate: true
  # Prefixed: a bare `private` scope would clash with Module#private.
  enum :sync_status, SYNC_STATUSES.index_with(&:itself), prefix: :sync, validate: true
  enum :sync_mode, SYNC_MODES.index_with(&:itself), validate: true

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    inverse_of: :linked_accounts
  has_many :unlocks,
    class_name: "UserAchievementUnlock",
    dependent: nil, # on delete cascade
    inverse_of: :linked_account
  has_many :set_progress,
    class_name: "UserAchievementSetProgress",
    dependent: nil, # on delete cascade
    inverse_of: :linked_account

  validates :external_id, presence: true, uniqueness: { scope: :provider }
  validates :provider, uniqueness: { scope: :user_id }

  # The Provider's accounts waiting for a listing, oldest first.
  scope :sync_due, lambda { |provider, now = Time.current|
    where(provider: provider, sync_due_at: ..now).order(:sync_due_at, :id)
  }

  # When Sync now is next allowed: `now`, or the end of the cooldown.
  def sync_available_at(now = Time.current)
    return now if sync_requested_at.nil?

    [ sync_requested_at + SYNC_COOLDOWN, now ].max
  end
end
