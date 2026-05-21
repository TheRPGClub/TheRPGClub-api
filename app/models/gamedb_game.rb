# frozen_string_literal: true

class GamedbGame < ApplicationRecord
  self.table_name = "gamedb_games"
  self.primary_key = "game_id"

  belongs_to :collection,
    class_name: "GamedbCollection",
    foreign_key: :collection_id,
    optional: true,
    inverse_of: :games

  has_many :releases,
    class_name: "GamedbRelease",
    foreign_key: :game_id,
    dependent: nil,
    inverse_of: :game
  has_many :images,
    class_name: "GamedbGameImage",
    foreign_key: :game_id,
    dependent: nil,
    inverse_of: :game
  has_many :game_platforms,
    class_name: "GamedbGamePlatform",
    foreign_key: :game_id,
    dependent: nil,
    inverse_of: :game
  has_many :platforms,
    through: :game_platforms,
    source: :platform

  has_many :game_companies,
    class_name: "GamedbGameCompany",
    foreign_key: :game_id,
    dependent: nil,
    inverse_of: :game
  has_many :companies,
    through: :game_companies,
    source: :company

  has_many :game_franchises,
    class_name: "GamedbGameFranchise",
    foreign_key: :game_id,
    dependent: nil,
    inverse_of: :game
  has_many :franchises,
    through: :game_franchises,
    source: :franchise

  has_many :game_genres,
    class_name: "GamedbGameGenre",
    foreign_key: :game_id,
    dependent: nil,
    inverse_of: :game
  has_many :genres,
    through: :game_genres,
    source: :genre

  has_many :game_modes,
    class_name: "GamedbGameMode",
    foreign_key: :game_id,
    dependent: nil,
    inverse_of: :game
  has_many :modes,
    through: :game_modes,
    source: :mode

  has_many :game_perspectives,
    class_name: "GamedbGamePerspective",
    foreign_key: :game_id,
    dependent: nil,
    inverse_of: :game
  has_many :perspectives,
    through: :game_perspectives,
    source: :perspective

  has_many :game_themes,
    class_name: "GamedbGameTheme",
    foreign_key: :game_id,
    dependent: nil,
    inverse_of: :game
  has_many :themes,
    through: :game_themes,
    source: :theme

  has_many :user_game_collections,
    class_name: "UserGameCollection",
    foreign_key: :gamedb_game_id,
    dependent: nil,
    inverse_of: :game
  has_many :user_game_completions,
    class_name: "UserGameCompletion",
    foreign_key: :gamedb_game_id,
    dependent: nil,
    inverse_of: :game
  has_many :user_favorites,
    class_name: "UserGameFavorite",
    foreign_key: :gamedb_game_id,
    dependent: nil,
    inverse_of: :game
  has_many :reviews,
    class_name: "UserGameReview",
    foreign_key: :gamedb_game_id,
    dependent: nil,
    inverse_of: :game
  has_many :user_backlog_entries,
    class_name: "UserGameBacklog",
    foreign_key: :gamedb_game_id,
    dependent: nil,
    inverse_of: :game
  has_many :gotm_entries,
    class_name: "GotmEntry",
    foreign_key: :gamedb_game_id,
    dependent: nil,
    inverse_of: :game
  has_many :nr_gotm_entries,
    class_name: "NrGotmEntry",
    foreign_key: :gamedb_game_id,
    dependent: nil,
    inverse_of: :game

  SUMMARY_COLUMNS = %i[
    game_id title description igdb_id slug total_rating igdb_url created_at updated_at
    featured_video_url initial_release_date collection_id parent_igdb_id parent_game_name
    thumbnail_bad thumbnail_approved
  ].freeze

  GOTM_WON_SQL = <<~SQL.squish.freeze
    EXISTS (SELECT 1 FROM gotm_entries WHERE gotm_entries.gamedb_game_id = gamedb_games.game_id)
  SQL
  NR_GOTM_WON_SQL = <<~SQL.squish.freeze
    EXISTS (SELECT 1 FROM nr_gotm_entries WHERE nr_gotm_entries.gamedb_game_id = gamedb_games.game_id)
  SQL

  scope :without_images, lambda {
    select(*SUMMARY_COLUMNS,
      "(#{GOTM_WON_SQL}) AS gotm_won",
      "(#{NR_GOTM_WON_SQL}) AS nr_gotm_won")
  }

  scope :gotm_winners, -> { where(GOTM_WON_SQL) }
  scope :nr_gotm_winners, -> { where(NR_GOTM_WON_SQL) }
  scope :any_winners, -> { where("#{GOTM_WON_SQL} OR #{NR_GOTM_WON_SQL}") }

  validates :title, presence: true

  def as_json(options = nil)
    super(options).except("total_rating").merge(
      "cover_url" => cover_url,
      "art_url" => art_url,
      "logo_url" => logo_url
    )
  end

  def cover_url
    primary_image_url("cover")
  end

  def art_url
    primary_image_url("artwork")
  end

  def logo_url
    primary_image_url("logo")
  end

  def primary_image_url(kind)
    if images.loaded?
      return images
        .select { |image| image.kind == kind }
        .sort_by { |image| [ image.is_primary ? 0 : 1, image.position.to_i, image.image_id.to_i ] }
        .first
        &.url
    end

    images.where(kind: kind).primary_first.first&.url
  end

  def self.search(query)
    escaped = sanitize_sql_like(query.to_s.strip)

    without_images
      .where(
        <<~SQL.squish,
          title ILIKE :term
          OR slug ILIKE :term
          OR EXISTS (
            SELECT 1
            FROM gamedb_search_synonyms s
            WHERE s.term_text ILIKE :term
              AND gamedb_games.title ILIKE '%' || s.term_text || '%'
          )
        SQL
        term: "%#{escaped}%"
      )
      .order(
        Arel.sql(
          sanitize_sql_array(
            [
              <<~SQL.squish,
                CASE
                  WHEN lower(title) = lower(:exact) THEN 0
                  WHEN title ILIKE :prefix THEN 1
                  ELSE 2
                END,
                total_rating DESC NULLS LAST,
                title ASC
              SQL
              { exact: query.to_s.strip, prefix: "#{escaped}%" }
            ]
          )
        )
      )
  end

  def alternate_games
    alternate_ids = GamedbGameAlternate
      .where("game_id = :id OR alt_game_id = :id", id: game_id)
      .pluck(:game_id, :alt_game_id)
      .flatten
      .uniq
      .excluding(game_id)

    GamedbGame.without_images.where(game_id: alternate_ids).order(:title)
  end
end
