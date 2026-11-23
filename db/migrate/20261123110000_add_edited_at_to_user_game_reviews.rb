# frozen_string_literal: true

# An Edit to a Published Review more than an hour after publishing marks it
# as edited (spec api#430, ticket #435, ADR 0013). Null means never edited
# past the grace; no edit history is kept.
class AddEditedAtToUserGameReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :user_game_reviews, :edited_at, :datetime
  end
end
