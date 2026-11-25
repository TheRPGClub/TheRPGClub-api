# frozen_string_literal: true

module Goty
  # The Year So Far's club releases (GLOSSARY "Year So Far"; spec api#481):
  # the games eligible for year Y's Game of the Year (Goty::Eligibility) that
  # at least one member has played, meaning holds a Game Completion, a Now
  # Playing entry or a Published Review of it. Each member counts once per
  # game; only current members count (no bots, none who left the server). Most played first, then by title, at most CAP games.
  #
  # These are not nominations: nothing here carries into the vote.
  #
  # Built in a fixed number of queries. Candidates come from the three
  # tables first, narrowed in SQL to games with any dated Release or an
  # initial release date in Y (a game whose earliest date is in Y has one
  # there), then Goty::Eligibility.check_all settles each.
  module ClubReleases
    CAP = 48
    # Every upcoming render (the bot's per-member panels, admin PATCH
    # responses) reads these, so the counted list is cached this long.
    CACHE_FOR = 5.minutes

    Row = Data.define(:game, :members_played)

    PLAYED_SQL = <<~SQL.squish.freeze
      SELECT plays.gamedb_game_id, gamedb_games.title, COUNT(*) AS members_played
      FROM (
        SELECT user_id, gamedb_game_id FROM user_game_completions
        UNION
        SELECT user_id, gamedb_game_id FROM user_now_playing WHERE gamedb_game_id IS NOT NULL
        UNION
        SELECT user_id, gamedb_game_id FROM user_game_reviews WHERE published_at IS NOT NULL
      ) plays
      JOIN rpg_club_users ON rpg_club_users.user_id = plays.user_id
        AND rpg_club_users.is_bot = false AND rpg_club_users.server_left_at IS NULL
      JOIN gamedb_games ON gamedb_games.game_id = plays.gamedb_game_id
      WHERE EXISTS (
          SELECT 1 FROM gamedb_releases
          WHERE gamedb_releases.game_id = plays.gamedb_game_id
            AND gamedb_releases.release_date >= :from_date AND gamedb_releases.release_date < :to_date
        )
        OR (gamedb_games.initial_release_date >= :from_time AND gamedb_games.initial_release_date < :to_time)
      GROUP BY plays.gamedb_game_id, gamedb_games.title
    SQL

    module_function

    # [Row(game: GamedbGame with images, members_played:)] for year Y.
    # The counts and eligibility are cached for CACHE_FOR; the games are
    # loaded fresh.
    def for(year)
      year = Integer(year)
      kept = Rails.cache.fetch([ "goty_club_releases", year ], expires_in: CACHE_FOR) { kept_rows(year) }
      games = GamedbGame.where(game_id: kept.map(&:first)).preload(:images).index_by(&:game_id)
      kept.filter_map do |game_id, members|
        game = games[game_id]
        Row.new(game: game, members_played: members) if game
      end
    end

    # [[gamedb_game_id, members_played]] for the eligible games, in order, at most CAP.
    def kept_rows(year)
      counted = played_rows(year).sort_by { |game_id, title, members| [ -members, title.to_s, game_id ] }
      eligible = Goty::Eligibility.check_all(counted.map(&:first), year)
      counted.select { |game_id, _, _| eligible.fetch(game_id).eligible? }.first(CAP)
        .map { |game_id, _, members| [ game_id, members ] }
    end

    # [[gamedb_game_id, title, members_played]] for the candidate games.
    def played_rows(year)
      from = Date.new(year, 1, 1)
      to = Date.new(year + 1, 1, 1)
      sql = GamedbGame.sanitize_sql_array([ PLAYED_SQL, { from_date: from, to_date: to,
        from_time: Time.utc(year, 1, 1), to_time: Time.utc(year + 1, 1, 1) } ])
      GamedbGame.connection.select_rows(sql, "Goty::ClubReleases").map do |game_id, title, members|
        [ Integer(game_id), title, Integer(members) ]
      end
    end
  end
end
