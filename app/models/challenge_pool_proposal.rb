# frozen_string_literal: true

# A Pool Proposal (GLOSSARY.md, "Pool Proposal"; spec api#442, ticket
# api#447): a member (`user_id`) asks for a game to join a Pool Challenge,
# with an optional `note` to whoever decides. It is pending until the Host
# (staff for a club-hosted Challenge) accepts it as a Core or Optional Game
# (`accepted_as`) or declines it; `decided_by` and `decided_at` say who and
# when. At most one proposal per game per Challenge is pending
# (ux_challenge_pool_proposals_one_pending). Challenges::PoolProposals makes
# and decides them.
class ChallengePoolProposal < ApplicationRecord
  STATUSES = %w[pending accepted declined].freeze
  ACCEPTED_AS = %w[core optional].freeze
  NOTE_MAX = 280

  belongs_to :challenge
  belongs_to :game, class_name: "GamedbGame", foreign_key: :game_id, inverse_of: false
  belongs_to :user, -> { without_images }, class_name: "RpgClubUser", foreign_key: :user_id, primary_key: :user_id,
    inverse_of: false
  belongs_to :decider, -> { without_images }, class_name: "RpgClubUser", foreign_key: :decided_by,
    primary_key: :user_id, optional: true, inverse_of: false

  validates :status, inclusion: { in: STATUSES }
  validates :accepted_as, inclusion: { in: ACCEPTED_AS }, allow_nil: true
  validates :note, length: { maximum: NOTE_MAX }

  normalizes :note, with: ->(value) { value.strip.presence }

  scope :pending, -> { where(status: "pending") }

  def pending? = status == "pending"
end
