# frozen_string_literal: true

# The per-category review scorecard (story, music, combat…) the web composer
# writes alongside the overall `rating`.
#
# Nullable with no default: a review with no scorecard ("quick take") is what
# every existing row already is, and stays a first-class choice rather than a
# missing value. The nested shape is validated in UserGameReview — a jsonb
# check constraint for it would be unwieldy — so none is added here.
class AddFacetsToUserGameReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :user_game_reviews, :facets, :jsonb
  end
end
