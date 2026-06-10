# frozen_string_literal: true

# A Discord forum thread the bot tracks (#45). Mapped to one or more games
# through `thread_game_links` (see ThreadGameLink); `gamedb_game_id` is a
# *derived* column carrying the thread's "primary" game (the MIN of its links),
# kept current server-side via .recompute_primary_game! whenever links change —
# clients never write it directly.
#
# Named DiscordThread, not Thread, because `Thread` is a Ruby core class —
# reopening it as an ActiveRecord model raises "superclass mismatch". The table
# is still `threads`. Writes are service/admin-gated (the bot writes through the
# API, replacing its direct SQL: upsertThread / setSkipLinking).
class DiscordThread < ApplicationRecord
  self.table_name = "threads"
  self.primary_key = "thread_id"

  # Columns the upsert (POST /threads) is allowed to refresh on an *existing*
  # row. `skip_linking` (an admin choice) and `created_at` are excluded so a
  # periodic sync sweep can't clobber them — mirroring the bot's upsertThread,
  # which leaves both untouched on MATCH and manages skip_linking separately.
  SYNC_COLUMNS = %w[forum_channel_id thread_name is_archived last_seen_at].freeze

  has_many :thread_game_links,
    class_name: "ThreadGameLink",
    foreign_key: :thread_id,
    primary_key: :thread_id,
    inverse_of: :thread,
    dependent: :delete_all

  has_many :games,
    through: :thread_game_links,
    source: :game

  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    primary_key: :game_id,
    optional: true,
    inverse_of: nil

  validates :forum_channel_id, :thread_name, presence: true
  validates :is_archived, :skip_linking, inclusion: { in: %w[Y N] }

  # Recompute the derived "primary" game (the MIN of the thread's linked game
  # ids, or NULL when it has none), mirroring the bot's updateThreadsGameId.
  # Called after any link change. `update_all` so we skip callbacks/validations
  # — threads has no `updated_at` to bump, and the value is server-derived.
  def self.recompute_primary_game!(thread_id)
    min = ThreadGameLink.where(thread_id: thread_id).minimum(:gamedb_game_id)
    where(thread_id: thread_id).update_all(gamedb_game_id: min)
  end
end
