# frozen_string_literal: true

module Challenges
  # Pool Proposals (GLOSSARY.md, "Pool Proposal"; spec api#442, ticket
  # api#447): any member who can see a Pool Challenge proposes a game for it,
  # and whoever may edit the Challenge (Actor#can_decide_proposals?) accepts
  # it as a Core or Optional Game, or declines it.
  #
  #   propose!  refuses a game already in the Pool (Core or Optional) or
  #             already pending; an excluded game may be proposed. Tells the
  #             Host, or #dev for a club-hosted Challenge
  #             (DirectMessages.pool_proposal!).
  #   accept!   puts the game in the Pool as `as` through Challenges::Form,
  #             lifting an exclusion, so Runs refresh and a new Core Game DMs
  #             the members in a Run as any Pool edit does. Tells the
  #             proposer (DirectMessages.pool_proposal_accepted!).
  #             With `add_to_list`, the game also goes into the linked
  #             Game List (Challenges::ListLink.add_games!).
  #   decline!  only marks it declined.
  #
  # Each runs under the Challenge's row lock, so two decisions, or a proposal
  # and an accept, never cross. Refusals raise Challenges::ProposalRefused or
  # (from the Pool edit) Challenges::Invalid.
  module PoolProposals
    UNPROCESSABLE = :unprocessable_content

    def self.propose!(challenge, user_id:, game_id:, note:)
      refuse_unless_pool(challenge)
      game = GamedbGame.find_by(game_id: parse_id(game_id))
      raise ProposalRefused.new("invalid_proposal", "game_id must be a GameDB game.", status: UNPROCESSABLE) unless game

      Challenge.transaction do
        challenge.lock!
        if PoolDefinition.of(challenge).games.exists?(game_id: game.game_id)
          raise ProposalRefused.new("already_in_pool", "#{game.title} is already in this Pool.")
        end

        refuse_pending(challenge, game)
        proposal = ChallengePoolProposal.new(challenge: challenge, game: game, user_id: user_id, note: note)
        unless proposal.valid?
          raise ProposalRefused.new("invalid_proposal", proposal.errors.full_messages.join(". "), status: UNPROCESSABLE)
        end

        proposal.save!
        DirectMessages.pool_proposal!(proposal)
        proposal
      end
    end

    # Accepts the pending `proposal` as a Core or Optional Game (`as`) for
    # the member `by`.
    def self.accept!(proposal, as:, by:, add_to_list: false)
      as = as.to_s
      unless ChallengePoolProposal::ACCEPTED_AS.include?(as)
        raise ProposalRefused.new("invalid_proposal", "as must be core or optional.", status: UNPROCESSABLE)
      end

      decide(proposal, by: by) do |challenge|
        challenge.updated_by = by
        Form.new(challenge, "pool" => pool_with(PoolDefinition.of(challenge), proposal.game_id, as)).save!
        ListLink.add_games!(challenge, [ proposal.game_id ]) if add_to_list
        proposal.update!(status: "accepted", accepted_as: as, decided_by: by, decided_at: Time.current)
        DirectMessages.pool_proposal_accepted!(proposal)
      end
    end

    def self.decline!(proposal, by:)
      decide(proposal, by: by) do
        proposal.update!(status: "declined", decided_by: by, decided_at: Time.current)
      end
    end

    def self.decide(proposal, by:)
      challenge = proposal.challenge
      Challenge.transaction do
        challenge.lock!
        proposal.lock!
        unless proposal.pending?
          raise ProposalRefused.new("already_decided", "This proposal was already #{proposal.status}.")
        end

        yield challenge
      end
      proposal
    end
    private_class_method :decide

    # The Pool's hand-picked lists with `game_id` moved to `as` and out of
    # the other two (so an exclusion lifts).
    def self.pool_with(definition, game_id, as)
      PoolSources::HAND_LISTS.to_h do |inclusion, key|
        ids = definition.public_send(key) - [ game_id ]
        [ key.to_s, inclusion == as ? ids + [ game_id ] : ids ]
      end
    end
    private_class_method :pool_with

    def self.refuse_pending(challenge, game)
      pending = ChallengePoolProposal.pending.find_by(challenge_id: challenge.id, game_id: game.game_id)
      return unless pending

      raise ProposalRefused.new("already_proposed", "#{game.title} has already been proposed for this Pool.",
        proposal_id: pending.id)
    end
    private_class_method :refuse_pending

    def self.refuse_unless_pool(challenge)
      return if challenge.challenge_format == Formats::Pool::KEY

      raise ProposalRefused.new("not_pool", "Only a Pool Challenge takes Pool Proposals.", status: UNPROCESSABLE)
    end
    private_class_method :refuse_unless_pool

    def self.parse_id(value)
      Integer(value.to_s, 10)
    rescue ArgumentError
      nil
    end
    private_class_method :parse_id
  end
end
