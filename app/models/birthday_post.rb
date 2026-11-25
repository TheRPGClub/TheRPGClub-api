# frozen_string_literal: true

# A member's Birthday Post for a calendar year (ticket #401): one per member
# and year (ux_birthday_posts_once), so the post is queued once however often
# the job runs and however the member's Birth Date changes. Written only by
# Birthdays::PostJob, when it queues the post.
class BirthdayPost < ApplicationRecord
  belongs_to :user, -> { without_images }, class_name: "RpgClubUser", foreign_key: :user_id, primary_key: :user_id, inverse_of: false
end
