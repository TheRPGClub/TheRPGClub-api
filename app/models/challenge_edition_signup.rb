# frozen_string_literal: true

# A member signed up for an Edition (spec #376, "Sign-up and pairing"). The
# draw either leaves them out (`left_out_at`: fewer than 5 games in their
# backlog by then) or gives them a recipient (`recipient_user_id`), the
# member they are the Santa of. Nobody but staff learns who a member's Santa
# is before the Edition ends.
class ChallengeEditionSignup < ApplicationRecord
  belongs_to :edition, class_name: "ChallengeEdition", inverse_of: :signups
  belongs_to :user, -> { without_images }, class_name: "RpgClubUser", foreign_key: :user_id, primary_key: :user_id,
    inverse_of: false

  scope :drawn, -> { where.not(recipient_user_id: nil) }

  def left_out? = left_out_at.present?
end
