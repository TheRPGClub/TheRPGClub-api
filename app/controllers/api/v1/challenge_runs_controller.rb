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

      before_action :require_acting_member!, only: %i[create abandon destroy slot_move past_pick past_play]

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
      # already have an Active Run of it. A Slots Run starting at the birth
      # year: 409 `birth_date_required` without a Birth Date, 422 `no_slots`
      # when the birth year is after the last year. `meta.notices` says what
      # the member should know, such as their birth year showing on the Run.
      def create
        challenge = visible_challenges.find(params[:challenge_id])
        run = Challenges::Runs.start!(challenge, actor.user_id)
        render_run(run, status: :created, meta: { notices: challenge.format_rules.notices(run) })
      end

      # POST /api/v1/challenge_runs/:id/abandon
      #
      # 409 `run_not_active` unless the Run is Active.
      def abandon
        own_run { |run| render_run(Challenges::Runs.abandon!(run)) }
      end

      # POST /api/v1/challenge_runs/:id/slot_move
      # Body: { "data": { "game_id": 12, "slot_year": 1999 } }
      #
      # Moves a Cleared game of the member's Slots Run to another open year
      # it fits. 422 `not_slots`, `not_cleared`, `slot_out_of_range` or
      # `slot_not_fitting`; 409 `slot_filled` (with the filling `game_id`)
      # or `run_not_active`.
      def slot_move
        data = request_data
        game_id = positive_integer(data["game_id"], "game_id")
        year = positive_integer(data["slot_year"], "slot_year")
        return if performed?

        own_run { |run| render_run(Challenges::Runs.move!(run, game_id: game_id, year: year)) }
      end

      # POST /api/v1/challenge_runs/:id/past_pick
      # Body: { "data": { "completion_id": 345, "slot_year": 1999 } }
      #
      # Counts past play: puts one of the member's Game Completions dated
      # before their Slots Run started (or undated) in an open year its game
      # fits. 422 `not_slots`, `past_play_off`, `not_past_completion`,
      # `already_cleared` (use a slot move), `slot_out_of_range` or
      # `slot_not_fitting`; 409 `slot_filled` (with the filling `game_id`) or
      # `run_not_active`.
      def past_pick
        data = request_data
        completion_id = positive_integer(data["completion_id"], "completion_id")
        year = positive_integer(data["slot_year"], "slot_year")
        return if performed?

        own_run do |run|
          render_run(Challenges::Runs.pick!(run, completion_id: completion_id, year: year))
        end
      end

      # GET /api/v1/challenge_runs/:id/past_play?q=chrono
      #
      # The member's earlier Game Completions they could pick for their Slots
      # Run now (past_pick), each with the open years its game fits, oldest
      # first and undated last; `q` narrows by title. Refused like past_pick.
      def past_play
        own_run do |run|
          rows = Challenges::Runs.past_play(run)
          titles = GamedbGame.where(game_id: rows.map { |completion, _| completion.game_id }).pluck(:game_id, :title).to_h
          query = params[:q].to_s.strip.downcase
          data = rows.filter_map do |completion, years|
            title = titles[completion.game_id]
            next if query.present? && !title.to_s.downcase.include?(query)

            { completion_id: completion.completion_id, game_id: completion.game_id, title: title,
              completed_at: completion.cleared_on&.iso8601, open_years: years }
          end
          render json: { data: data }
        end
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

      def positive_integer(value, field)
        Integer(value.to_s, 10).tap { |int| raise ArgumentError unless int.positive? }
      rescue ArgumentError
        render(json: { error: "#{field} must be a whole number" }, status: :bad_request) unless performed?
        nil
      end

      def readable_runs
        runs = ChallengeRun.where(challenge_id: visible_challenges.select(:id))
        runs = runs.or(ChallengeRun.where(user_id: actor.user_id)) if actor.user_id.present?
        runs
      end

      # Staff (Moderators and above) see an Assignment Run's Santa before
      # the Edition ends.
      def resource_params = { staff: actor.moderator_or_above? }

      def render_runs(scope)
        status = params[:status].presence
        if status && !ChallengeRun::STATUSES.include?(status)
          return render(json: { error: "status must be one of #{ChallengeRun::STATUSES.join(', ')}" },
            status: :bad_request)
        end

        scope = scope.where(status: status) if status
        render_collection(ChallengeRunResource.preloaded(scope), resource: ChallengeRunResource,
          default_order: { started_at: :desc, id: :desc }, params: resource_params)
      end

      def render_run(run, status: :ok, meta: nil)
        run = ChallengeRunResource.preloaded(ChallengeRun.where(id: run.id)).first!
        body = { data: ChallengeRunResource.new(run, params: resource_params).serializable_hash }
        body[:meta] = meta if meta
        render json: body, status: status
      end
    end
  end
end
