# frozen_string_literal: true

# Revisions (spec api#430, ticket #433): dated returns to a Published Review,
# each a Draft until its author publishes it. The latest Published Revision's
# score is the Review's current score; deleting the Review deletes its
# Revisions.
class CreateUserGameReviewRevisions < ActiveRecord::Migration[8.1]
  def change
    create_table :user_game_review_revisions, primary_key: :revision_id do |t|
      t.bigint :review_id, null: false
      t.integer :rating
      t.string :title, limit: 120
      t.jsonb :body
      t.jsonb :facets
      t.datetime :published_at
      t.datetime :edited_at
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: false, default: -> { "CURRENT_TIMESTAMP" }

      t.index %i[review_id published_at], name: "ix_user_game_review_revisions_review"
      # At most one Draft Revision per Review at a time.
      t.index :review_id, name: "uq_user_game_review_revisions_one_draft", unique: true,
        where: "published_at IS NULL"
      t.check_constraint "rating >= 0 AND rating <= 100", name: "ck_user_game_review_revisions_rating_range"
      t.check_constraint "published_at IS NULL OR rating IS NOT NULL",
        name: "ck_user_game_review_revisions_rating_when_published"
    end

    add_foreign_key :user_game_review_revisions, :user_game_reviews, column: :review_id,
      primary_key: :review_id, on_delete: :cascade, name: "fk_user_game_review_revisions_review"
  end
end
