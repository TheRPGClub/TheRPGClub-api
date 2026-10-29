# frozen_string_literal: true

module Imports
  # The server-side Steam collection import workflow (web-parity #289), ported
  # from the bot's collection-steam-import.command.ts so a signed-in member
  # can drive their own import from the web.
  #
  #   Imports::SteamWorkflow.item_rows(import_id, library[:games])  # rows for insert_all
  #
  # Authorization and TestModeRollback are the caller's job: the controllers
  # check the import's owner and wrap each request's writes.
  class SteamWorkflow
    # Insert rows for a Steam::Client#owned_games library, row_index 1..n
    # (as the bot numbers them).
    def self.item_rows(import_id, games)
      games.each_with_index.map do |game, index|
        {
          import_id: import_id,
          row_index: index + 1,
          steam_app_id: game[:app_id],
          steam_app_name: game[:name],
          playtime_forever_min: game[:playtime_forever_minutes],
          playtime_windows_min: game[:playtime_windows_minutes],
          playtime_mac_min: game[:playtime_mac_minutes],
          playtime_linux_min: game[:playtime_linux_minutes],
          playtime_deck_min: game[:playtime_deck_minutes],
          last_played_at: game[:last_played_at],
          status: "pending"
        }
      end
    end
  end
end
