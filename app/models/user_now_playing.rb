# frozen_string_literal: true

class UserNowPlaying < ApplicationRecord
  self.table_name = "user_now_playing"
  self.primary_key = "entry_id"

  # The bot caps a user's now-playing list at 10 entries; the API enforces the
  # same ceiling on create so a migrated `/now-playing add` can't exceed it.
  MAX_ENTRIES = 10

  # Correlates a `user_game_journal_entries` row to the now-playing (user, game)
  # pair, for the journal aggregates the bot's `getNowPlaying` derives via SQL.
  JOURNAL_CORRELATION =
    "je.user_id = user_now_playing.user_id AND je.gamedb_game_id = user_now_playing.gamedb_game_id"
  # The game's linked Discord thread. `gamedb_games` has no `linked_thread_id`
  # column in this schema, so this mirrors the bot's legacy fallback: the lowest
  # `thread_game_links.thread_id`, else the lowest `threads.thread_id`.
  LINKED_THREAD_SQL = <<~SQL.squish.freeze
    COALESCE(
      (SELECT MIN(tgl.thread_id) FROM thread_game_links tgl
        WHERE tgl.gamedb_game_id = user_now_playing.gamedb_game_id),
      (SELECT MIN(th.thread_id) FROM threads th
        WHERE th.gamedb_game_id = user_now_playing.gamedb_game_id)
    )
  SQL

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    optional: true,
    inverse_of: :now_playing_entries
  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    optional: true,
    inverse_of: :user_now_playing_entries
  belongs_to :platform,
    class_name: "GamedbPlatform",
    foreign_key: :platform_id,
    optional: true,
    inverse_of: :user_now_playing_entries

  # Augments each row with the journal aggregates and the derived linked-thread
  # id the bot's now-playing UI reads (#104). Required by the resources that
  # serialize `has_journal_entry`/`journal_count`/`last_journal_at` and the
  # `game.linked_thread_id` embed; serialized without it those fields default.
  scope :with_now_playing_details, lambda {
    select(
      "user_now_playing.*",
      "EXISTS (SELECT 1 FROM user_game_journal_entries je WHERE #{JOURNAL_CORRELATION}) AS has_journal_entry",
      "(SELECT COUNT(*) FROM user_game_journal_entries je WHERE #{JOURNAL_CORRELATION}) AS journal_count",
      "(SELECT MAX(je.created_at) FROM user_game_journal_entries je WHERE #{JOURNAL_CORRELATION}) AS last_journal_at",
      "(#{LINKED_THREAD_SQL}) AS linked_thread_id"
    )
  }

  validates :note, length: { maximum: 500 }, allow_nil: true
  # One entry per (user, game), matching the `uq_user_now_playing_gamedb` unique
  # index — surfaced as a 422 rather than a DB 500.
  validates :gamedb_game_id, uniqueness: { scope: :user_id }, allow_nil: true
  validate :within_entry_limit, on: :create

  # Append new entries after the user's current highest position so the bot's
  # ascending `sort_order` display order is preserved without the client
  # supplying it (the bot assigns `MAX(sort_order) + 1` the same way).
  before_create :assign_sort_order
  # Stamp `note_updated_at` whenever the note changes (set to now when a note is
  # present, cleared to null when blank) — the bot's note edit flow reads it.
  before_save :stamp_note_updated_at, if: :note_changed?

  private

  def assign_sort_order
    return if sort_order.present?

    max = self.class.where(user_id: user_id).maximum(:sort_order) || 0
    self.sort_order = max + 1
  end

  def stamp_note_updated_at
    self.note_updated_at = note.present? ? Time.current : nil
  end

  def within_entry_limit
    return if user_id.blank?
    return if self.class.where(user_id: user_id).count < MAX_ENTRIES

    errors.add(:base, "user already has the maximum of #{MAX_ENTRIES} now-playing entries")
  end
end
