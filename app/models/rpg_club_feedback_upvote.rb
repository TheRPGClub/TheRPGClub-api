# frozen_string_literal: true

# A member's upvote on Feedback; one per member per Feedback. On a Bug Report
# it reads "I hit this too".
class RpgClubFeedbackUpvote < ApplicationRecord
  self.table_name = "rpg_club_feedback_upvotes"

  belongs_to :feedback, class_name: "RpgClubFeedback", inverse_of: :upvotes
  belongs_to :user, -> { without_images }, class_name: "RpgClubUser", primary_key: :user_id, inverse_of: false
end
