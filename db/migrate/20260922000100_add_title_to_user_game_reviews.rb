# frozen_string_literal: true

# A short, optional title for a review, alongside the existing free-form
# `body`. Nullable with no default: an untitled review ("quick take" or an
# older row) is a first-class choice, not a missing value. Capped at 120
# characters to match the composer's own client-side limit.
class AddTitleToUserGameReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :user_game_reviews, :title, :string, limit: 120
  end
end
