# frozen_string_literal: true

module Api
  module V1
    # Editions (GLOSSARY.md, "Edition"; spec #376, ticket #383): the yearly
    # cycles of an Assignment (Secret Santa) Challenge. Members read them and
    # sign up or withdraw before the sign-up cutoff (Challenges::Editions).
    # Gated by the `challenges` Feature.
    #
    # The bot acts for the member it names (ChallengeActing): a sign-up needs
    # `data.acting_user_id`, a withdrawal (DELETE) `acting_user_id` in the
    # query, and reads take it in the query for `signed_up`. Editions of a
    # hidden Challenge are found only by those who may see the Challenge.
    class ChallengeEditionsController < ApplicationController
      include ChallengeActing

      feature :challenges

      before_action :require_acting_member!, only: %i[sign_up withdraw santa pick]

      rescue_from Challenges::SignupRefused do |error|
        render json: { error: error.code, message: error.message, **error.details }, status: error.status
      end

      # GET /api/v1/challenges/:challenge_id/editions
      #
      # The Challenge's Editions, newest first.
      def index
        challenge = visible_challenges.where(challenge_format: Challenges::Formats::Assignment::KEY)
          .find(params[:challenge_id])
        render_collection(ChallengeEditionResource.preloaded(challenge.editions), resource: ChallengeEditionResource,
          default_order: { year: :desc }, params: resource_params)
      end

      # GET /api/v1/challenge_editions/:id
      def show
        render_edition(find_edition)
      end

      # POST /api/v1/challenge_editions/:id/signup
      # Body (bot only): { "data": { "acting_user_id": "..." } }
      #
      # 409 `signup_closed` from the cutoff on, 409 `already_signed_up`, 422
      # `backlog_too_small` (with `minimum` and `backlog_count`) below the
      # 5-game backlog minimum.
      def sign_up
        render_edition(Challenges::Editions.sign_up!(find_edition, actor.user_id))
      end

      # DELETE /api/v1/challenge_editions/:id/signup
      #
      # 409 `signup_closed` from the cutoff on, 409 `not_signed_up`.
      def withdraw
        render_edition(Challenges::Editions.withdraw!(find_edition, actor.user_id))
      end

      # GET /api/v1/challenge_editions/:id/santa?q=chrono
      #
      # The acting member's side as a Santa (Challenges::Picks): their
      # recipient, their pick, the deadline, and the recipient's backlog minus
      # the games they have Cleared, which `q` narrows by title. 403
      # `not_a_santa` for anyone the draw didn't make a Santa (or who
      # withdrew), so nobody else reads it.
      def santa
        edition = find_edition
        render_santa(edition, Challenges::Picks.santa!(edition, actor.user_id))
      end

      # PUT /api/v1/challenge_editions/:id/santa/pick
      # Body: { "data": { "game_id": 123 } } (the bot adds `acting_user_id`)
      #
      # Picks (or changes) the game, until the start of the pick deadline day:
      # 409 `picks_closed` from then on, 422 `not_eligible` for a game not in
      # the recipient's backlog or already Cleared by them.
      def pick
        game_id = Integer(request_data["game_id"].to_s, 10)
        edition = find_edition
        render_santa(edition, Challenges::Picks.pick!(edition, actor.user_id, game_id))
      rescue ArgumentError
        render json: { error: "game_id must be a whole number" }, status: :bad_request
      end

      private

      def render_santa(edition, signup)
        backlog = Challenges::Picks.eligible_backlog(signup.recipient_user_id).preload(:game, :platform)
        query = params[:q].to_s.strip
        backlog = backlog.joins(:game).where("gamedb_games.title ILIKE ?", "%#{ApplicationRecord.sanitize_sql_like(query)}%") if query.present?
        picked = signup.picked_game
        render json: { data: {
          edition_id: edition.id, year: edition.year,
          recipient: Challenges.member(signup.recipient),
          pick: picked && { game: GameSummaryResource.new(picked).serializable_hash,
                            picked_at: signup.picked_at, picked_randomly: signup.picked_randomly },
          pick_deadline_on: edition.pick_deadline_on.iso8601,
          picks_open: Challenges::Picks.open?(edition),
          backlog: BacklogEntryResource.new(backlog.order(:sort_order, :entry_id).to_a).serializable_hash
        } }
      end


      def find_edition
        challenges = visible_challenges.where(challenge_format: Challenges::Formats::Assignment::KEY)
        ChallengeEdition.where(challenge_id: challenges.select(:id)).find(params[:id])
      end

      def resource_params = { user_id: actor.user_id, today: Challenges.today, staff: actor.moderator_or_above? }

      def render_edition(edition)
        edition = ChallengeEditionResource.preloaded(ChallengeEdition.where(id: edition.id)).first!
        render json: { data: ChallengeEditionResource.new(edition, params: resource_params).serializable_hash }
      end
    end
  end
end
