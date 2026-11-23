# frozen_string_literal: true

# The bot's scraped HowLongToBeat cache (one row per game, enforced by the
# unique index on `gamedb_game_id`). Third-party data that lives in the shared
# DB; the aggregate game profile (#115) serves it so the bot's `/gamedb view`
# path needs no direct-SQL read. The `game` FK is bot-sourced and unenforced, so
# the association is optional.
class RpgClubHltbCache < ApplicationRecord
  self.table_name = "rpg_club_hltb_cache"
  self.primary_key = "cache_id"

  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    primary_key: :game_id,
    optional: true,
    inverse_of: :hltb_cache

  # How often a member may force a fresh HowLongToBeat search for a game whose
  # times are saved (spec api#437); Admins and above are exempt.
  FORCE_INTERVAL = 30.days

  # When a member may next force a search: nil when they may now (never
  # searched, or searched FORCE_INTERVAL ago).
  def next_forced_search_at
    allowed_at = searched_at && searched_at + FORCE_INTERVAL
    allowed_at if allowed_at && allowed_at > Time.current
  end
end
