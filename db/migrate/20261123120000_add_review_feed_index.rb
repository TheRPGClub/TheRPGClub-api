# frozen_string_literal: true

# The Review Feed (spec api#430, ticket #432) reads Published Reviews newest
# published first, as does the Latest Reviews Dashboard Panel.
class AddReviewFeedIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :user_game_reviews, %i[published_at review_id], name: "ix_user_game_reviews_feed",
      order: { published_at: :desc, review_id: :desc }, where: "published_at IS NOT NULL"
  end
end
