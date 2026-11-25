# frozen_string_literal: true

module Api
  module V1
    # Game of the Year nominations for a GOTY Vote (spec api#471, ticket
    # api#473). The rules (window, eligibility, the cap of three) live in
    # Goty::Nominate; this controller owns who may act for whom.
    #
    # Anyone who can use the Feature reads every nomination. A member
    # nominates and withdraws only their own; the service token (the bot's
    # `/goty nominate`) names the member in `user_id`. Admins and the service
    # may remove any nomination until voting opens; an owner only while
    # nominating.
    class GotyNominationsController < ApplicationController
      feature :goty_vote

      # GET /api/v1/goty_votes/:goty_vote_year/nominations[?user_id=]
      def index
        vote = GotyVote.find(params[:goty_vote_year])
        scope = vote.nominations.preload(:user, game: [ :images, :platforms ])
        scope = scope.where(user_id: params[:user_id].to_s) if params[:user_id].present?
        render_collection(scope, resource: GotyNominationResource, default_order: { nominated_at: :asc, id: :asc })
      end

      # POST /api/v1/goty_votes/:goty_vote_year/nominations: 201 for a new
      # nomination, 200 when the member had already nominated the game and
      # only its reason changed.
      def create
        data = params.require(:data)
        game_id = data.require(:gamedb_game_id)
        user_id = nominator_id(data[:user_id]) or return

        result = Goty::Nominate.call(year: params[:goty_vote_year], user_id: user_id, gamedb_game_id: game_id,
          reason: data[:reason])
        render json: { data: GotyNominationResource.new(preloaded(result.nomination)).serializable_hash },
          status: result.created? ? :created : :ok
      rescue Goty::Nominate::NominationsClosedError => error
        render_error("nominations_closed", error.message)
      rescue Goty::Nominate::CapReachedError => error
        render_error("nomination_cap_reached", error.message)
      rescue Goty::Nominate::IneligibleError => error
        render_error(error.reason, error.message)
      end

      # DELETE /api/v1/goty_votes/:goty_vote_year/nominations/:id
      def destroy
        vote = GotyVote.find(params[:goty_vote_year])
        nomination = vote.nominations.find(params[:id])
        staff = admin_or_service?
        unless staff || own?(nomination.user_id)
          return render json: { error: "forbidden" }, status: :forbidden
        end

        open = staff ? Time.current < vote.voting_opens_at : vote.nominations_open?
        unless open
          return render_error("nominations_closed",
            "Game of the Year nominations for #{vote.year} can no longer be withdrawn: voting has opened")
        end

        nomination.destroy!
        render json: { deleted: true }
      end

      private

      # The member a nomination is for: the signed-in member themselves, or
      # the member the service names. Renders and returns nil otherwise.
      def nominator_id(requested)
        requested = requested.to_s.presence
        if current_principal&.service?
          return render_error("user_id_required", "the service must name the member in user_id") if requested.nil?
          return requested if RpgClubUser.exists?(user_id: requested)

          return render json: { error: "not_found", message: "no member #{requested}" }, status: :not_found
        end
        return current_principal.id.to_s if current_principal&.discord_user? && (requested.nil? || own?(requested))

        render json: { error: "forbidden" }, status: :forbidden
        nil
      end

      def own?(user_id)
        current_principal&.discord_user? && current_principal.id.to_s == user_id.to_s
      end

      def preloaded(nomination)
        ActiveRecord::Associations::Preloader.new(records: [ nomination ],
          associations: [ :user, { game: %i[images platforms] } ]).call
        nomination
      end

      def render_error(code, message)
        render json: { error: code, message: message }, status: :unprocessable_content
        nil
      end
    end
  end
end
