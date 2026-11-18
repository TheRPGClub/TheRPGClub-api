# frozen_string_literal: true

# A member signed up for an Edition (spec #376, "Sign-up and pairing"). The
# draw either leaves them out (`left_out_at`: fewer than 5 games in their
# backlog by then) or gives them a recipient (`recipient_user_id`), the
# member they are the Santa of. Nobody but staff learns who a member's Santa
# is before the Edition ends.
#
# A Santa picks one game for their recipient (`picked_game_id`, ticket #384)
# before the pick deadline; a recipient whose Santa has no pick by then
# (missed it, withdrew after the draw (`withdrawn_at`), or left the server
# before picking) gets a random pick at the deadline (`picked_randomly`). The pick is revealed on the reveal date and
# becomes the recipient's Run goal. A Santa who withdraws loses their pick
# but keeps `picked_at`, which marks the recipient picked while Santas pick
# (ChallengeEditionResource), so that withdrawing doesn't show whose Santa
# they were.
class ChallengeEditionSignup < ApplicationRecord
  belongs_to :edition, class_name: "ChallengeEdition", inverse_of: :signups
  belongs_to :user, -> { without_images }, class_name: "RpgClubUser", foreign_key: :user_id, primary_key: :user_id,
    inverse_of: false

  belongs_to :recipient, -> { without_images }, class_name: "RpgClubUser", foreign_key: :recipient_user_id,
    primary_key: :user_id, optional: true, inverse_of: false
  belongs_to :picked_game, class_name: "GamedbGame", optional: true, inverse_of: false

  scope :drawn, -> { where.not(recipient_user_id: nil) }

  def left_out? = left_out_at.present?

  def withdrawn? = withdrawn_at.present?
end
