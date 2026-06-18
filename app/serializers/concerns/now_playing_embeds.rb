# frozen_string_literal: true

# The embedded `game` and `platform` shapes shared by the now-playing entry
# resources that carry them (NowPlayingEntryResource, the user's own list, and
# NowPlayingMemberEntryResource, the cross-member view). The game-scoped
# variant (NowPlayingUserEntryResource) embeds neither, so it does not include
# this.
#
# Both reuse the shared trimmed resources and merge in the one extra field the
# bot's now-playing display needs (#104), so the shared GameSummaryResource /
# PlatformResource contracts used elsewhere are untouched:
#   - `game.linked_thread_id`        — the game's linked Discord thread, derived
#                                       by `UserNowPlaying.with_now_playing_details`
#                                       (null on a record loaded without it).
#   - `platform.platform_abbreviation` — the abbreviation used in display labels
#                                       (e.g. "Hades (PC)"), a real column on the
#                                       preloaded platform.
# Each embed renders `null` when the entry has no associated game / platform.
module NowPlayingEmbeds
  extend ActiveSupport::Concern

  included do
    # String keys (Alba's serializable_hash key type) so the merged field is not
    # an odd symbol-keyed entry in an otherwise string-keyed hash.
    attribute :game do |entry|
      next nil unless entry.game

      GameSummaryResource.new(entry.game).serializable_hash.merge(
        "linked_thread_id" => (entry["linked_thread_id"] if entry.has_attribute?("linked_thread_id"))
      )
    end

    attribute :platform do |entry|
      next nil unless entry.platform

      PlatformResource.new(entry.platform).serializable_hash.merge(
        "platform_abbreviation" => entry.platform.platform_abbreviation
      )
    end
  end
end
