# frozen_string_literal: true

# An entry's Playtime on a member's shelf list (spec api#457, ticket api#460):
# `playtime_minutes`, the member's Playtime for the entry's game (0 when they
# have none, null for an entry with no game). Present only when the list
# hands in its Playtime::Ledger as `shelf_playtime` (ShelfPlaytime), so the
# single-entry and write responses that share these resources stay as they
# were. `playthrough_minutes: true` also adds `playthrough_minutes`, the open
# Playthrough's time (null when none is open), for Now Playing.
module ShelfPlaytimeFields
  def self.with(playthrough_minutes: false)
    Module.new do
      extend ActiveSupport::Concern

      included do
        attribute :playtime_minutes, if: proc { params.key?(:shelf_playtime) } do |entry|
          params[:shelf_playtime].total_minutes(entry.user_id, entry.gamedb_game_id) if entry.gamedb_game_id
        end

        next unless playthrough_minutes

        attribute :playthrough_minutes, if: proc { params.key?(:shelf_playtime) } do |entry|
          params[:shelf_playtime].for(entry.user_id, entry.gamedb_game_id).playthrough_minutes if entry.gamedb_game_id
        end
      end
    end
  end
end
