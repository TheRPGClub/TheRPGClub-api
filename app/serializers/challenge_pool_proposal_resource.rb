# frozen_string_literal: true

# A Pool Proposal as the API serves it (spec api#442, ticket api#447): the
# game, who proposed it and their note, and where it stands. Load proposals
# through ChallengePoolProposalResource.preloaded.
class ChallengePoolProposalResource
  include BaseResource

  attributes :id, :challenge_id

  attribute :game do |proposal|
    game = proposal.game
    { game_id: game.game_id, title: game.title, cover_url: game.cover_url }
  end

  attribute :proposer do |proposal|
    Challenges.member(proposal.user)
  end

  attributes :note, :status, :accepted_as

  attribute :decider do |proposal|
    proposal.decider && Challenges.member(proposal.decider)
  end

  attributes :decided_at, :created_at, :updated_at

  PRELOADS = [ :user, :decider, { game: :images } ].freeze

  def self.preloaded(scope) = scope.preload(*PRELOADS)

  def self.serialize(proposal)
    new(preloaded(ChallengePoolProposal.where(id: proposal.id)).first!).serializable_hash
  end
end
