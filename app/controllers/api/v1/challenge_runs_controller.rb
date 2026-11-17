# frozen_string_literal: true

module Api
  module V1
    # Runs (GLOSSARY.md, "Run"; spec #376, ticket #378). A member starts a Run
    # of an Open Challenge, abandons it, and deletes it once it has ended;
    # members read anyone's Runs with their progress, which fills in by
    # itself from Game Completions and Now Playing (Challenges::Progress).
    # Gated by the `challenges` Feature.
    #
    # The bot acts for the member it names (ChallengeActing): writes need
    # `data.acting_user_id` (a DELETE: `acting_user_id` in the query). Only
    # the Run's own member may abandon or delete it.
    #
    # Runs of a hidden Challenge are listed only for those who may see the
    # Challenge (Moderators and above, its Host) and for the Run's member.
    class ChallengeRunsController < ApplicationController
      include ChallengeActing

      feature :challenges

      before_action :require_acting_member!, only: %i[create abandon destroy]

      rescue_from Challenges::RunRefused do |error|
        render json: { error: error.code, message: error.message, **error.details }, status: error.status
      end

      NOT_YOURS = "You can only change your own Runs."

      # GET /api/v1/users/:user_id/challenge_runs?status=active
      #
      # The member's Runs, current and past, newest first, for their profile.
      def user_index
        render_runs(readable_runs.where(user_id: params[:user_id].to_s))
      end

      # GET /api/v1/challenges/:challenge_id/runs?status=active
      #
      # The Challenge's Runs, newest first.
      def challenge_index
        challenge = visible_challenges.find(params[:challenge_id])
        render_runs(readable_runs.where(challenge_id: challenge.id))
      end

      # GET /api/v1/challenge_runs/:id
      def show
        render_run(readable_runs.find(params[:id]))
      end

      # POST /api/v1/challenges/:challenge_id/runs
      # Body (bot only): { "data": { "acting_user_id": "..." } }
      #
      # Starts the acting member's Run. 409 `challenge_closed` when the
      # Challenge is Closed, 409 `run_active` (with `run_id`) when they
      # already have an Active Run of it.
      def create
        challenge = visible_challenges.find(params[:challenge_id])
        render_run(Challenges::Runs.start!(challenge, actor.user_id), status: :created)
      end

      # POST /api/v1/challenge_runs/:id/abandon
      #
      # 409 `run_not_active` unless the Run is Active.
      def abandon
        own_run { |run| render_run(Challenges::Runs.abandon!(run)) }
      end

      # DELETE /api/v1/challenge_runs/:id
      #
      # 409 `run_active` for an Active Run, which is abandoned first.
      def destroy
        own_run do |run|
          Challenges::Runs.delete!(run)
          render json: { data: { id: run.id, deleted: true } }
        end
      end

      private

      def own_run
        run = ChallengeRun.find(params[:id])
        return forbid(NOT_YOURS) unless actor.user_id.present? && run.user_id == actor.user_id

        yield run
      end

      def readable_runs
        runs = ChallengeRun.where(challenge_id: visible_challenges.select(:id))
        runs = runs.or(ChallengeRun.where(user_id: actor.user_id)) if actor.user_id.present?
        runs
      end

      def render_runs(scope)
        status = params[:status].presence
        if status && !ChallengeRun::STATUSES.include?(status)
          return render(json: { error: "status must be one of #{ChallengeRun::STATUSES.join(', ')}" },
            status: :bad_request)
        end

        scope = scope.where(status: status) if status
        render_collection(ChallengeRunResource.preloaded(scope), resource: ChallengeRunResource,
          default_order: { started_at: :desc, id: :desc })
      end

      def render_run(run, status: :ok)
        run = ChallengeRunResource.preloaded(ChallengeRun.where(id: run.id)).first!
        render json: { data: ChallengeRunResource.new(run).serializable_hash }, status: status
      end
    end
  end
end
