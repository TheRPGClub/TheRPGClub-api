# frozen_string_literal: true

# A Review is a Draft until its author publishes it (spec api#430, ticket
# #431). `published_at` replaces the never-cleared `is_shared` flag: null is a
# Draft, set once on publish and never cleared. A Draft may have no score yet,
# so `rating` turns nullable, and a check constraint keeps a Published Review
# from ever being without one.
#
# The owner empties user_game_reviews before deploy, but every shared Review
# still left is backfilled as Published on its creation date before
# `is_shared` goes, so a missed manual step can't turn them all into Drafts.
class MakeReviewsDraftOrPublished < ActiveRecord::Migration[8.1]
  def change
    add_column :user_game_reviews, :published_at, :datetime
    reversible do |direction|
      direction.up do
        execute "UPDATE user_game_reviews SET published_at = created_at WHERE is_shared"
      end
    end
    change_column_null :user_game_reviews, :rating, true
    add_check_constraint :user_game_reviews, "published_at IS NULL OR rating IS NOT NULL",
      name: "ck_user_game_reviews_rating_when_published"
    remove_column :user_game_reviews, :is_shared, :boolean, default: true, null: false
  end
end
