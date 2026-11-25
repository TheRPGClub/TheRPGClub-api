# frozen_string_literal: true

# Manual Playtime (GLOSSARY.md, ADR 0015): time a member records for a game
# themselves, against one platform (null is "Other"). One entry per member,
# game and platform. It adds to the Provider figures; Playtime::Ledger is the
# one place the sum is worked out.
#
# `origin` says who wrote it: the member, or the launch seed from Game
# Completions (`playtime:seed_from_completions`). `keeps_over_provider` is the
# Provider whose figure on this platform the member chose not to count
# ("keep mine" on a mismatch).
class UserGameManualPlaytime < ApplicationRecord
  ORIGINS = %w[member completion_seed].freeze
  NOTE_MAX = 280

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    inverse_of: false
  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    primary_key: :game_id,
    inverse_of: false
  belongs_to :platform,
    class_name: "GamedbPlatform",
    foreign_key: :platform_id,
    primary_key: :platform_id,
    optional: true,
    inverse_of: false

  enum :origin, ORIGINS.index_with(&:itself), validate: true

  validates :minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :note, length: { maximum: NOTE_MAX }
  validates :keeps_over_provider, inclusion: { in: UserLinkedAccount::PROVIDERS }, allow_nil: true
end
