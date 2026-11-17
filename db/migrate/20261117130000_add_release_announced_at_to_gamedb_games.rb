# frozen_string_literal: true

# Release Calendar (api#391, ADR 0009): a game is announced once. Its sent
# announcement lives on the announced Release and goes with it when an IGDB
# refresh removes that Release, so the game keeps when it was announced here
# and the due feed never offers another of its Releases.
class AddReleaseAnnouncedAtToGamedbGames < ActiveRecord::Migration[8.1]
  def change
    add_column :gamedb_games, :release_announced_at, :datetime
  end
end
