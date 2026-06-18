# frozen_string_literal: true

# The consumer-audited now-playing allowlist (#36, extended for the bot's
# now-playing migration in #104), shared by the game-embedded
# (NowPlayingEntryResource), user-embedded (NowPlayingUserEntryResource) and
# cross-member (NowPlayingMemberEntryResource) variants of the same entry.
#
# Reads the entry PK (`entry_id`), `user_id` (game-scoped lists dedup players by
# it), `gamedb_game_id`, `platform_id`, `note`, plus the ordering/timing columns
# the bot's list and edit flows need: `sort_order` (ascending display order),
# `added_at` and `note_updated_at`.
#
# The three journal fields are correlated aggregates from
# `user_game_journal_entries` keyed by the entry's (user, game) pair — they gate
# the journal buttons/note editing in the bot UI. They are populated only when
# the record is loaded through `UserNowPlaying.with_now_playing_details`; read
# off a plain record (e.g. an unscoped embed) they default to "no journal".
module NowPlayingFields
  extend ActiveSupport::Concern

  included do
    attributes :entry_id, :user_id, :gamedb_game_id, :platform_id, :note,
      :sort_order, :added_at, :note_updated_at

    attribute :has_journal_entry do |entry|
      entry.has_attribute?("has_journal_entry") ? entry["has_journal_entry"] : false
    end

    attribute :journal_count do |entry|
      entry.has_attribute?("journal_count") ? entry["journal_count"].to_i : 0
    end

    attribute :last_journal_at do |entry|
      entry["last_journal_at"] if entry.has_attribute?("last_journal_at")
    end
  end
end
