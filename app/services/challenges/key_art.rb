# frozen_string_literal: true

module Challenges
  # A Challenge's key art (spec #376; the website's Challenge banner): the
  # picture behind its banner and on its posts, as an image URL, or nil.
  #
  # For a Pool Challenge it is the artwork of the first game in its Pool, by
  # title, that has artwork (the game's primary artwork); with no artwork in
  # the Pool, the first game's cover the same way. Slots and Assignment
  # Challenges have none: the bot and the website draw their Format's
  # picture (a slot grid, Secret Santa's doors) in the tint instead.
  module KeyArt
    KINDS_SQL = "gamedb_game_images.kind = 'artwork' DESC"
    private_constant :KINDS_SQL

    def self.url(challenge)
      return nil unless challenge.challenge_format == Formats::Pool::KEY

      GamedbGameImage.joins(:game).where(kind: %w[artwork cover], game_id: PoolDefinition.of(challenge).games.select(:game_id))
        .order(Arel.sql(KINDS_SQL), "gamedb_games.title", "gamedb_games.game_id")
        .merge(GamedbGameImage.primary_first).first&.url
    end
  end
end
