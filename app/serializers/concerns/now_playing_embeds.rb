# frozen_string_literal: true

# The embedded `game` and `platform` shapes shared by the now-playing entry
# resources that carry them (NowPlayingEntryResource, the user's own list, and
# NowPlayingMemberEntryResource, the cross-member view). The game-scoped
# variant (NowPlayingUserEntryResource) embeds neither, so it does not include
# this.
#
# The `game` embed reuses the shared GameSummaryResource and merges in the one
# extra field the bot's now-playing display needs (#104) — `linked_thread_id`,
# the game's linked Discord thread derived by
# `UserNowPlaying.with_now_playing_details` (null on a record loaded without it)
# — so the shared GameSummaryResource contract used elsewhere is untouched. The
# `platform` embed is the plain PlatformResource: `platform_abbreviation` (the
# abbreviation used in display labels, e.g. "Hades (PC)") now lives on that
# shared resource directly (#106), so no per-entry merge is needed.
#
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

    one :platform, resource: PlatformResource
  end
end
