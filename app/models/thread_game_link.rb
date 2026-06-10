# frozen_string_literal: true

# Join row linking a Discord thread (DiscordThread) to a game (#45). Composite
# primary key (thread_id, gamedb_game_id); the bot is the sole writer. A thread
# can link to several games and a game to several threads, so this is the
# canonical many-to-many the `GET /games/:id/threads` endpoint resolves.
class ThreadGameLink < ApplicationRecord
  self.table_name = "thread_game_links"
  self.primary_key = %i[thread_id gamedb_game_id]

  belongs_to :thread,
    class_name: "DiscordThread",
    foreign_key: :thread_id,
    primary_key: :thread_id,
    inverse_of: :thread_game_links

  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    primary_key: :game_id,
    inverse_of: nil
end
