# frozen_string_literal: true

module Api
  module V1
    # Votes on GOTM / Non-RPG GOTM nominations for a voting round (#173). The voting
    # rules (window, per-user cap, toggle/evict) live in Voting::CastVote;
    # this controller owns who may cast and who may see what, and when.
    #
    # Votes are anonymous while a round's voting window is open: everyone may
    # read the per-nomination tally (counts only), a voter may read their own
    # votes, and only admin/service may read identified vote rows (the bot
    # needs them to tally and announce results). Once voting has ended
    # (VotingRound.ended?), identified rows open up to any
    # authenticated caller.
    #
    # Casting is owner-gated: the service token may cast on behalf of any
    # user, a logged-in user only for themselves. The round-scoped DELETE is
    # the admin reset, mirroring the nominations one.
    #
    # A round with a tie-breaker runoff has a second ballot. Casts go to
    # whichever ballot is open; the reads and the reset take `runoff=true` to
    # address the runoff instead of the main vote, and runoff votes stay
    # anonymous while the runoff is open, like the main vote.
    #
    # The two backing tables share an identical shape, so each public action
    # is a thin GOTM/NR-GOTM pair delegating to a model-agnostic private
    # helper, like NominationsController.
    class VotesController < ApplicationController
      before_action :require_owner!,            only: %i[create_gotm create_nr_gotm]
      before_action :require_admin_or_service!, only: %i[destroy_all_gotm destroy_all_nr_gotm]

      # Caller-settable fields on a cast. `round_number` comes from the path
      # and `gamedb_game_id`/`voted_at` are derived, so none are accepted.
      WRITABLE_ATTRS = %w[user_id nomination_id].freeze

      # GET /api/v1/gotm_entries/:round/votes
      def gotm
        render_votes(GotmVote)
      end

      # GET /api/v1/nr_gotm_entries/:round/votes
      def nr_gotm
        render_votes(NrGotmVote)
      end

      # GET /api/v1/gotm_entries/:round/votes/tally
      def gotm_tally
        render_tally(GotmVote, GotmNomination)
      end

      # GET /api/v1/nr_gotm_entries/:round/votes/tally
      def nr_gotm_tally
        render_tally(NrGotmVote, NrGotmNomination)
      end

      # GET /api/v1/gotm_entries/:round/votes/:user_id
      def show_gotm
        render_user_votes(GotmVote)
      end

      # GET /api/v1/nr_gotm_entries/:round/votes/:user_id
      def show_nr_gotm
        render_user_votes(NrGotmVote)
      end

      # POST /api/v1/gotm_entries/:round/votes
      def create_gotm
        cast_vote("gotm")
      end

      # POST /api/v1/nr_gotm_entries/:round/votes
      def create_nr_gotm
        cast_vote("nr_gotm")
      end

      # DELETE /api/v1/gotm_entries/:round/votes
      def destroy_all_gotm
        destroy_all_votes(GotmVote)
      end

      # DELETE /api/v1/nr_gotm_entries/:round/votes
      def destroy_all_nr_gotm
        destroy_all_votes(NrGotmVote)
      end

      private

      # Cast or toggle a vote. 201 when a vote was placed, 200 when the cast
      # toggled an existing vote off. The response always carries the action,
      # any removed/evicted votes and a human-readable warning so the caller
      # can tell the voter what was replaced or taken back, and `runoff` says
      # which ballot the cast went to.
      def cast_vote(category)
        data = request_data.slice(*WRITABLE_ATTRS)
        result = Voting::CastVote.new(category: category).cast!(
          round_number: params[:round],
          user_id: data["user_id"],
          nomination_id: data["nomination_id"]
        )

        render json: { data: {
          action: result.action,
          vote: result.vote && VoteResource.new(result.vote).serializable_hash,
          removed_votes: result.removed_votes.map { |vote| VoteResource.new(vote).serializable_hash },
          cap: result.cap,
          runoff: result.runoff,
          warning: result.warning
        } }, status: result.action == "voted" ? :created : :ok
      rescue Voting::CastVote::VotingClosedError => error
        render json: { error: "voting_closed", message: error.message }, status: :unprocessable_entity
      rescue Voting::CastVote::NominationNotFoundError => error
        render json: { error: "nomination_not_found", message: error.message }, status: :not_found
      rescue Voting::CastVote::NominationMissingGameError => error
        render json: { error: "nomination_missing_game", message: error.message }, status: :unprocessable_entity
      rescue Voting::CastVote::GameNotInRunoffError => error
        render json: { error: "not_in_runoff", message: error.message }, status: :unprocessable_entity
      end

      # The identified round list — voter ids attached. Anonymous while the
      # window is open, so until voting has ended it stays admin/service-only.
      def render_votes(vote_model)
        return forbidden! unless admin_or_service? || voting_ended?

        scope = ballot(vote_model).preload(:user, game: :images)

        render_collection(scope, resource: VoteResource,
          default_order: { voted_at: :asc, vote_id: :asc })
      end

      # The anonymous tally: votes per nomination, no voter identities — safe
      # for any authenticated caller at any time. Unpaginated: bounded by the
      # round's nominations. Nominations with zero votes have no row. `meta`
      # carries the ballot's per-user vote cap so clients can render "vote for
      # up to N" before the user has cast anything.
      def render_tally(vote_model, nomination_model)
        rows = ballot(vote_model)
          .group(:nomination_id, :gamedb_game_id)
          .select(:nomination_id, :gamedb_game_id, "COUNT(*) AS vote_count")
          .order(Arel.sql("COUNT(*) DESC"), :nomination_id)

        render json: {
          data: VoteTallyResource.new(rows).serializable_hash,
          meta: { cap: tally_cap(nomination_model), runoff: runoff? }
        }
      end

      # A single voter's votes for the round (at most the cap, so no
      # pagination; an empty array when they have none). Their own votes are
      # always visible to them; everyone else waits for the window to end,
      # except admin/service.
      def render_user_votes(vote_model)
        return forbidden! unless admin_or_service? || own_votes? || voting_ended?

        votes = ballot(vote_model)
          .where(user_id: params[:user_id])
          .preload(:user, game: :images)
          .order(voted_at: :asc, vote_id: :asc)

        render json: { data: VoteResource.new(votes).serializable_hash }
      end

      # DELETE /.../votes — clears every vote on the round's ballot (the admin
      # reset, mirroring the nominations one). Always round-scoped, so the
      # whole table can never be wiped.
      def destroy_all_votes(vote_model)
        count = ballot(vote_model).delete_all
        render json: { deleted: true, count: count }
      end

      # require_owner! for the casts resolves the voter from the request body.
      def resolve_owner_id
        params.dig(:data, :user_id).presence
      end

      def own_votes?
        current_principal&.discord_user? && current_principal.id.to_s == params[:user_id].to_s
      end

      def voting_ended?
        VotingRound.ended?(params[:round], runoff: runoff?)
      end

      # The round's votes on the ballot the request addresses.
      def ballot(vote_model)
        vote_model.where(round_number: params[:round], runoff: runoff?)
      end

      def runoff?
        ActiveModel::Type::Boolean.new.cast(params[:runoff]) || false
      end

      def tally_cap(nomination_model)
        return Voting::CastVote::RUNOFF_CAP if runoff?

        Voting::CastVote.cap_for(nomination_model, params[:round])
      end

      def forbidden!
        render json: { error: "forbidden" }, status: :forbidden
        false
      end
    end
  end
end
