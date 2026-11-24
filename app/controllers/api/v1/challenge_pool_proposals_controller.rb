# frozen_string_literal: true

module Api
  module V1
    # Pool Proposals (GLOSSARY.md, "Pool Proposal"; spec api#442, ticket
    # api#447): any member who can see a Pool Challenge proposes a game; the
    # Host, or any Moderator or above, accepts it
    # as a Core or Optional Game or declines it (Challenges::PoolProposals).
    # Gated by the `challenges` Feature.
    #
    # The bot acts for the member it names (ChallengeActing): writes need
    # `data.acting_user_id`, and reads take `acting_user_id` in the query.
    class ChallengePoolProposalsController < ApplicationController
      include ChallengeActing

      feature :challenges

      before_action :require_acting_member!, only: %i[create accept decline]

      rescue_from Challenges::ProposalRefused do |error|
        render json: { error: error.code, message: error.message, **error.details }, status: error.status
      end
      rescue_from Challenges::Invalid do |error|
        render json: { error: "invalid_challenge", message: error.message }, status: :unprocessable_content
      end
      rescue_from GameLists::Refused do |error|
        render json: { error: error.code, message: error.message, **error.details }, status: error.status
      end

      # GET /api/v1/challenges/:challenge_id/pool_proposals?status=pending
      #
      # Newest first. Deciders see every proposal; other members their own.
      def index
        challenge = find_challenge
        scope = ChallengePoolProposal.where(challenge_id: challenge.id)
        scope = scope.where(user_id: actor.user_id.to_s) unless actor.can_decide_proposals?(challenge)
        status = params[:status].presence
        if status
          unless ChallengePoolProposal::STATUSES.include?(status)
            return render json: { error: "status must be pending, accepted or declined" }, status: :bad_request
          end

          scope = scope.where(status: status)
        end

        render_collection(ChallengePoolProposalResource.preloaded(scope), resource: ChallengePoolProposalResource,
          default_order: { created_at: :desc, id: :desc })
      end

      # POST /api/v1/challenges/:challenge_id/pool_proposals
      # Body: { "data": { "game_id": 12, "note": "..." } }
      def create
        data = request_data
        proposal = Challenges::PoolProposals.propose!(find_challenge, user_id: actor.user_id,
          game_id: data["game_id"], note: data["note"]&.to_s)
        render_proposal(proposal, status: :created)
      end

      # POST /api/v1/challenges/:challenge_id/pool_proposals/:id/accept
      # Body: { "data": { "as": "core" | "optional", "add_to_list": true } }
      #
      # `add_to_list` also adds the game to the linked Game List; only who
      # may touch that list (Actor#can_add_to_list?).
      def accept
        data = request_data
        as = data["as"]
        add = ActiveModel::Type::Boolean.new.cast(data["add_to_list"]) ? true : false
        decide do |proposal|
          challenge = proposal.challenge
          if add
            raise Challenges::Invalid, "This Challenge has no linked Game List to add to" unless challenge.pool_game_list_id
            unless actor.can_add_to_list?(challenge, challenge.pool_game_list)
              next forbid(Challenges::Refusals::ADD_TO_LIST)
            end
          end

          Challenges::PoolProposals.accept!(proposal, as: as, by: actor.user_id, add_to_list: add)
        end
      end

      # POST /api/v1/challenges/:challenge_id/pool_proposals/:id/decline
      def decline
        decide { |proposal| Challenges::PoolProposals.decline!(proposal, by: actor.user_id) }
      end

      private

      def find_challenge
        visible_challenges.find(params[:challenge_id])
      end

      def decide
        challenge = find_challenge
        return forbid(Challenges::Refusals::DECIDE_PROPOSALS) unless actor.can_decide_proposals?(challenge)

        proposal = ChallengePoolProposal.where(challenge_id: challenge.id).find(params[:id])
        decided = yield(proposal)
        render_proposal(decided) unless performed?
      end

      def render_proposal(proposal, status: :ok)
        render json: { data: ChallengePoolProposalResource.serialize(proposal) }, status: status
      end
    end
  end
end
