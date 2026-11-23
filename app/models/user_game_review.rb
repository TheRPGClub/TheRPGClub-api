# frozen_string_literal: true

class UserGameReview < ApplicationRecord
  self.table_name = "user_game_reviews"
  self.primary_key = "review_id"

  # The 7-day score lock and the edited marker (ADR 0013).
  include EditRules
  # The score, title and scorecard every take shares, with their validation.
  include ReviewTake

  belongs_to :user,
    class_name: "RpgClubUser",
    foreign_key: :user_id,
    primary_key: :user_id,
    inverse_of: :reviews
  belongs_to :game,
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    inverse_of: :reviews
  # The same game read through `GamedbGame.without_images` and
  # `with_track_months`, so it carries the `gotm_won` / `nr_gotm_won` track
  # flags and the month each was won (TrackedGameResource).
  belongs_to :tracked_game, -> { without_images.with_track_months },
    class_name: "GamedbGame",
    foreign_key: :gamedb_game_id,
    inverse_of: false,
    optional: true
  # The database deletes a Review's Revisions with it.
  has_many :revisions,
    class_name: "UserGameReviewRevision",
    dependent: nil,
    inverse_of: :review
  # The Published Revisions in publish order.
  has_many :published_revisions, -> { published.order(:published_at, :revision_id) },
    class_name: "UserGameReviewRevision",
    dependent: nil,
    inverse_of: :review
  # The latest Published Revision, whose score is the Review's current score.
  has_one :latest_revision, -> { published.order(published_at: :desc, revision_id: :desc) },
    class_name: "UserGameReviewRevision",
    dependent: nil,
    inverse_of: :review
  # The Draft Revision, if the author is Revisiting.
  has_one :draft_revision, -> { drafts },
    class_name: "UserGameReviewRevision",
    dependent: nil,
    inverse_of: :review

  # Every list, preview and count other members see covers Published
  # Reviews only (spec api#430); `published` and `drafts` come with
  # ReviewTake.

  # True when the body holds any text, in any of its three shapes (an editor
  # value, a bare string, an object from the pre-web import under one of the
  # keys summary, text, body or content), mirroring `reviewBodyText` in
  # `www/lib/api/review-body.ts`. A Review without it is a score-only quick
  # take, which the Review Feed's Written only filter drops.
  WRITTEN_SQL = <<~'SQL'.squish.freeze
    CASE jsonb_typeof(user_game_reviews.body)
      WHEN 'array' THEN jsonb_path_exists(user_game_reviews.body,
        'lax $.**.text ? (@.type() == "string" && @ like_regex "[^[:space:]]")')
      WHEN 'string' THEN btrim(user_game_reviews.body #>> '{}') <> ''
      WHEN 'object' THEN COALESCE(
        (jsonb_typeof(user_game_reviews.body -> 'summary') = 'string'
          AND btrim(user_game_reviews.body ->> 'summary') <> '')
        OR (jsonb_typeof(user_game_reviews.body -> 'text') = 'string'
          AND btrim(user_game_reviews.body ->> 'text') <> '')
        OR (jsonb_typeof(user_game_reviews.body -> 'body') = 'string'
          AND btrim(user_game_reviews.body ->> 'body') <> '')
        OR (jsonb_typeof(user_game_reviews.body -> 'content') = 'string'
          AND btrim(user_game_reviews.body ->> 'content') <> ''),
        false)
      ELSE false
    END
  SQL

  # Every take, Reviews and Revisions alike, as one row each in the Review's
  # columns, in place of the table (aliased `user_game_reviews`, so the
  # scopes here and the `user` / `tracked_game` associations still apply).
  # `state` is :published or :drafts. On top of the columns each row carries:
  #
  # - `kind`: "review" or "revision".
  # - `revision_id`: the Revision, null on a review.
  # - `previous_rating`: the score a Revision replaces, null on a review. For
  #   a Published Revision it is the score just before it was published (the
  #   Published Revision before it, else the Review's own); for a Draft
  #   Revision, the Review's current score.
  #
  # `user_id` and `gamedb_game_id` are the Review's. The rows are read-only.
  scope :takes, lambda { |state|
    published = { published: "IS NOT NULL", drafts: "IS NULL" }.fetch(state)
    from(<<~SQL.squish).readonly
      (
        SELECT r.review_id, r.user_id, r.gamedb_game_id, r.rating, r.title, r.body, r.facets,
          r.created_at, r.updated_at, r.published_at, r.edited_at,
          'review'::text AS kind, NULL::bigint AS revision_id, NULL::integer AS previous_rating
        FROM user_game_reviews r
        WHERE r.published_at #{published}
        UNION ALL
        SELECT r.review_id, r.user_id, r.gamedb_game_id, v.rating, v.title, v.body, v.facets,
          v.created_at, v.updated_at, v.published_at, v.edited_at,
          'revision'::text, v.revision_id,
          COALESCE((
            SELECT p.rating FROM user_game_review_revisions p
            WHERE p.review_id = v.review_id AND p.published_at IS NOT NULL
              AND p.revision_id <> v.revision_id
              AND (v.published_at IS NULL OR (p.published_at, p.revision_id) < (v.published_at, v.revision_id))
            ORDER BY p.published_at DESC, p.revision_id DESC LIMIT 1
          ), r.rating)
        FROM user_game_review_revisions v
        JOIN user_game_reviews r ON r.review_id = v.review_id
        WHERE v.published_at #{published}
      ) AS user_game_reviews
    SQL
  }

  scope :written, -> { where(WRITTEN_SQL) }
  # Selects the `written` flag alongside every column, for the Review Feed.
  scope :with_written, -> { select(arel_table[Arel.star], "(#{WRITTEN_SQL}) AS written") }

  validates :user_id, :gamedb_game_id, presence: true
  validates :user_id, uniqueness: { scope: :gamedb_game_id }

  # The Review's score: its latest Published Revision's, or its own until it
  # has one. `rating` stays the original take's score.
  def current_rating
    latest_revision ? latest_revision.rating : rating
  end

  # The Published Revisions in publish order, each told the score it
  # replaced (`previous_rating`).
  def revision_history
    previous = rating
    published_revisions.each do |revision|
      revision.previous_rating = previous
      previous = revision.rating
    end
  end

  # The full Review shape: `rating` is the current score, `original_rating`
  # the original take's, and `revisions` the Published Revisions in publish
  # order (spec api#430).
  def serializable_hash(options = nil)
    super.merge(
      "rating" => current_rating,
      "original_rating" => rating,
      "revisions" => revision_history.map(&:as_json)
    )
  end
end
