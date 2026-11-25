# frozen_string_literal: true

module Franchises
  # The /franchises index (spec api#487, ticket api#488): the current
  # Franchises (merged ones are left out) with what a tile shows.
  #
  #   browse = Franchises::Browse.new(q: "fantasy", letter: "F", sort: "games")
  #   page = browse.scope            # a relation to paginate
  #   browse.rows(page)              # the tiles
  #   Franchises::Browse.progress(ids, user_id)
  #
  # Each row: `{ franchise_id, name, games_count, mainline_count,
  # spin_off_count, add_on_count, first_year, latest_year, club_plays,
  # covers }`. Counts follow Gamedb::FranchiseGames: an Add-on (a game with a
  # parent) counts as an Add-on whatever its Mainline mark, and a Spin-off is
  # the rest. The years span every linked game's release. `club_plays` is
  # Now Playing entries plus Game Completions in the last 90 days, on any
  # linked game. `covers` is up to three `{ game_id, title, cover_url }`,
  # newest Mainline first, then Spin-offs, newest first, games with a cover
  # only.
  #
  # Sorts: `az` (name), `games` (most linked games), `plays` (most Club
  # plays). Franchises with no games always come last. `letter` is A to Z,
  # or `#` for names that don't start with a letter.
  class Browse
    SORTS = %w[az games plays].freeze
    LETTERS = [ *"A".."Z", "#" ].freeze
    PLAYS_WINDOW = 90.days
    COVERS = 3

    STATS_SQL = <<~SQL.squish.freeze
      LEFT JOIN (
        SELECT gf.franchise_id,
          COUNT(*) AS games_count,
          COUNT(*) FILTER (WHERE gf.mainline AND g.parent_igdb_id IS NULL) AS mainline_count,
          COUNT(*) FILTER (WHERE g.parent_igdb_id IS NOT NULL) AS add_on_count,
          MIN(EXTRACT(YEAR FROM g.initial_release_date))::int AS first_year,
          MAX(EXTRACT(YEAR FROM g.initial_release_date))::int AS latest_year
        FROM gamedb_game_franchises gf
        JOIN gamedb_games g ON g.game_id = gf.game_id
        GROUP BY gf.franchise_id
      ) stats ON stats.franchise_id = gamedb_franchises.franchise_id
    SQL

    PLAYS_SQL = <<~SQL.squish.freeze
      LEFT JOIN (
        SELECT gf.franchise_id, COUNT(*) AS club_plays
        FROM gamedb_game_franchises gf
        JOIN (
          SELECT gamedb_game_id FROM user_now_playing WHERE gamedb_game_id IS NOT NULL
          UNION ALL
          SELECT gamedb_game_id FROM user_game_completions WHERE completed_at >= :since
        ) plays ON plays.gamedb_game_id = gf.game_id
        GROUP BY gf.franchise_id
      ) plays ON plays.franchise_id = gamedb_franchises.franchise_id
    SQL

    EMPTY_LAST = "COALESCE(stats.games_count, 0) = 0"
    BY_NAME = "LOWER(gamedb_franchises.name) ASC, gamedb_franchises.franchise_id ASC"
    ORDERS = {
      "az" => "#{EMPTY_LAST}, #{BY_NAME}",
      "games" => "#{EMPTY_LAST}, COALESCE(stats.games_count, 0) DESC, #{BY_NAME}",
      "plays" => "#{EMPTY_LAST}, COALESCE(plays.club_plays, 0) DESC, COALESCE(stats.games_count, 0) DESC, #{BY_NAME}"
    }.freeze

    COLUMNS = <<~SQL.squish.freeze
      gamedb_franchises.franchise_id, gamedb_franchises.name,
      COALESCE(stats.games_count, 0) AS games_count,
      COALESCE(stats.mainline_count, 0) AS mainline_count,
      COALESCE(stats.add_on_count, 0) AS add_on_count,
      stats.first_year, stats.latest_year,
      COALESCE(plays.club_plays, 0) AS club_plays
    SQL

    COVERS_SQL = <<~SQL.squish.freeze
      SELECT franchise_id, game_id, title FROM (
        SELECT gf.franchise_id, g.game_id, g.title,
          ROW_NUMBER() OVER (PARTITION BY gf.franchise_id
            ORDER BY gf.mainline DESC, g.initial_release_date DESC NULLS LAST, g.game_id DESC) AS place
        FROM gamedb_game_franchises gf
        JOIN gamedb_games g ON g.game_id = gf.game_id
        WHERE gf.franchise_id IN (:ids) AND g.parent_igdb_id IS NULL
          AND EXISTS (SELECT 1 FROM gamedb_game_images i WHERE i.game_id = g.game_id AND i.kind = 'cover')
      ) ranked
      WHERE place <= :covers
      ORDER BY franchise_id, place
    SQL

    def initialize(q: nil, letter: nil, sort: nil)
      @q = q.to_s.strip
      @letter = letter.presence
      @sort = sort.presence || "az"
    end

    def scope
      relation = GamedbFranchise.current
        .joins(STATS_SQL)
        .joins(ApplicationRecord.sanitize_sql([ PLAYS_SQL, { since: PLAYS_WINDOW.ago } ]))
        .select(COLUMNS)
        .order(Arel.sql(ORDERS.fetch(@sort)))
      relation = relation.where("gamedb_franchises.name ILIKE ?", "%#{GamedbFranchise.sanitize_sql_like(@q)}%") if @q.present?
      by_letter(relation)
    end

    # The tiles for a page of `scope`.
    def rows(franchises)
      covers = covers_for(franchises.map(&:franchise_id))
      franchises.map do |franchise|
        counts = franchise.attributes.slice("games_count", "mainline_count", "add_on_count")
        { franchise_id: franchise.franchise_id, name: franchise.name,
          games_count: counts["games_count"], mainline_count: counts["mainline_count"],
          spin_off_count: counts["games_count"] - counts["mainline_count"] - counts["add_on_count"],
          add_on_count: counts["add_on_count"],
          first_year: franchise["first_year"], latest_year: franchise["latest_year"],
          club_plays: franchise["club_plays"], covers: covers.fetch(franchise.franchise_id, []) }
      end
    end

    # A member's Mainline progress in each Franchise, as Franchises::Progress
    # counts it: `{ franchise_id => { done, total } }`, `{ done: 0, total:
    # 0 }` for a Franchise with no Mainline games.
    def self.progress(franchise_ids, user_id)
      done = ApplicationRecord.sanitize_sql([ <<~SQL.squish, user_id.to_s ])
        COUNT(*) FILTER (WHERE EXISTS (SELECT 1 FROM user_game_completions c
          WHERE c.gamedb_game_id = gamedb_game_franchises.game_id AND c.user_id = ?))
      SQL
      counts = GamedbGameFranchise.where(franchise_id: franchise_ids, mainline: true)
        .joins(:game).where(gamedb_games: { parent_igdb_id: nil })
        .group(:franchise_id).pluck(:franchise_id, Arel.sql("COUNT(*)"), Arel.sql(done))
        .to_h { |id, total, finished| [ id, { done: finished, total: total } ] }
      franchise_ids.index_with { |id| counts.fetch(id, { done: 0, total: 0 }) }
    end

    private

    def by_letter(relation)
      return relation if @letter.nil?
      return relation.where("gamedb_franchises.name !~* '^[a-z]'") if @letter == "#"

      relation.where("gamedb_franchises.name ILIKE ?", "#{@letter}%")
    end

    def covers_for(ids)
      return {} if ids.empty?

      games = GamedbGame.find_by_sql([ COVERS_SQL, { ids: ids, covers: COVERS } ])
      images = GamedbGameImage.where(game_id: games.map(&:game_id), kind: "cover").primary_first
        .group_by(&:game_id)
      games.group_by(&:franchise_id).transform_values do |picks|
        picks.map { |game| { game_id: game.game_id, title: game.title, cover_url: images[game.game_id]&.first&.url } }
      end
    end
  end
end
