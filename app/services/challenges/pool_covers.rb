# frozen_string_literal: true

module Challenges
  # The first games of several Pools at once, for cover walls and list
  # flyers: `{ game_id, title, cover_url }` (cover_url null for a game without
  # one), those with a cover first, then by title, then id. One query ranks
  # every Pool's games (the same Pool rule as PoolDefinition#games), one more
  # reads the games and their images.
  #
  #   Challenges::PoolCovers.of([ 3, 7 ], limit: 4) # => { 3 => [ { game_id:, title:, cover_url: }, ... ], 7 => [] }
  module PoolCovers
    def self.of(challenge_ids, limit:)
      covers = challenge_ids.to_h { |id| [ id, [] ] }
      return covers if challenge_ids.empty?

      rows = ActiveRecord::Base.connection.select_rows(
        ActiveRecord::Base.sanitize_sql_array([ RANKED_SQL, { ids: challenge_ids, limit: limit } ])
      )
      games = GamedbGame.where(game_id: rows.map(&:last)).select(:game_id, :title).preload(:images).index_by(&:game_id)
      rows.each do |challenge_id, game_id|
        game = games.fetch(game_id)
        covers[challenge_id] << { game_id: game.game_id, title: game.title, cover_url: game.cover_url }
      end
      covers
    end

    RANKED_SQL = <<~SQL.squish.freeze
      WITH sourced AS (
        SELECT pf.challenge_id, gf.game_id FROM challenge_pool_franchises pf
          JOIN gamedb_game_franchises gf ON gf.franchise_id = pf.franchise_id
          WHERE pf.challenge_id IN (:ids)
        UNION
        SELECT pc.challenge_id, g.game_id FROM challenge_pool_collections pc
          JOIN gamedb_games g ON g.collection_id = pc.collection_id
          WHERE pc.challenge_id IN (:ids)
      ), pool AS (
        SELECT s.challenge_id, s.game_id FROM sourced s
          WHERE NOT EXISTS (SELECT 1 FROM challenge_pool_games x WHERE x.challenge_id = s.challenge_id
            AND x.game_id = s.game_id AND x.inclusion = 'exclude')
        UNION
        SELECT challenge_id, game_id FROM challenge_pool_games WHERE inclusion = 'include' AND challenge_id IN (:ids)
      )
      SELECT challenge_id, game_id FROM (
        SELECT pool.challenge_id, pool.game_id, ROW_NUMBER() OVER (
          PARTITION BY pool.challenge_id
          ORDER BY EXISTS (SELECT 1 FROM gamedb_game_images i WHERE i.game_id = g.game_id AND i.kind = 'cover') DESC,
            g.title, g.game_id
        ) AS place
        FROM pool JOIN gamedb_games g ON g.game_id = pool.game_id
      ) ranked
      WHERE place <= :limit
      ORDER BY challenge_id, place
    SQL
    private_constant :RANKED_SQL
  end
end
