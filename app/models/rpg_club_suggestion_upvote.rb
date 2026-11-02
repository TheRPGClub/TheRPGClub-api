# frozen_string_literal: true

# A member's upvote on a Suggestion; one per member per Suggestion.
class RpgClubSuggestionUpvote < ApplicationRecord
  self.table_name = "rpg_club_suggestion_upvotes"

  belongs_to :suggestion, class_name: "RpgClubSuggestion", inverse_of: :upvotes
  belongs_to :user, class_name: "RpgClubUser", primary_key: :user_id, inverse_of: false
end
