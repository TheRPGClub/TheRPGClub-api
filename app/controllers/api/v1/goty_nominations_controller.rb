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
    # nominating. An Admin removing someone else's nomination gives a reason
    # and the bot announces it, as for GOTM nominations (#332).
    class GotyNominationsController < ApplicationController
      include ActsForMember

      feature :goty_vote

      # The bot's own limit on the deletion reason modal, as for GOTM.
      REMOVAL_REASON_MAX = NominationsController::REMOVAL_REASON_MAX

      # GET /api/v1/goty_votes/:goty_vote_year/nominations[?user_id=]
      def index
        vote = GotyVote.find(params[:goty_vote_year])
        scope = vote.nominations.preload(:user, game: [ :images, :platforms ])
        scope = scope.where(user_id: params[:user_id].to_s) if params[:user_id].present?
        render_collection(scope, resource: GotyNominationResource, default_order: { nominated_at: :asc, id: :asc })
      end

      # POST /api/v1/goty_votes/:goty_vote_year/nominations: 201 for a new
      # nomination, 200 (and no change) when the member had already
      # nominated the game.
      def create
        data = params.require(:data)
        game_id = data.require(:gamedb_game_id)
        user_id = acting_member_id(data[:user_id]) or return

        result = Goty::Nominate.call(year: params[:goty_vote_year], user_id: user_id, gamedb_game_id: game_id)
        render json: { data: GotyNominationResource.new(preloaded(result.nomination)).serializable_hash },
          status: result.created? ? :created : :ok
      rescue Goty::Nominate::NominationsClosedError => error
        render_error("nominations_closed", error.message)
      rescue Goty::Nominate::CapReachedError => error
        render_error("nomination_cap_reached", error.message)
      rescue Goty::Nominate::IneligibleError => error
        render_error(error.reason, error.message)
      end

      # DELETE /api/v1/goty_votes/:goty_vote_year/nominations/:id[?reason=]
      #
      # A staff removal of someone else's nomination needs a `reason` and
      # queues a goty_nomination_deleted job announcing it, in the same
      # transaction. Owners and the service keep the plain delete.
      # `meta.announce_job_id` is that job, null when none was queued.
      def destroy
        vote = GotyVote.find(params[:goty_vote_year])
        nomination = vote.nominations.preload(:user, :game).find(params[:id])
        staff = admin_or_service?
        unless staff || own?(nomination.user_id)
          return render json: { error: "forbidden" }, status: :forbidden
        end

        open = staff ? Time.current < vote.voting_opens_at : vote.nominations_open?
        unless open
          return render_error("nominations_closed",
            "Game of the Year nominations for #{vote.year} can no longer be withdrawn: voting has opened")
        end

        reason = params[:reason].to_s.strip
        announce = staff_removal?(nomination)
        return if announce && !valid_removal_reason?(reason)

        announce_job = GotyNomination.transaction do
          nomination.destroy!
          enqueue_removal_notice(nomination, reason) if announce
        end
        render json: { deleted: true, meta: { announce_job_id: announce_job&.id } }
      end

      private

      # A signed-in member (necessarily Admin and up, past the owner gate)
      # removing a nomination that is not theirs.
      def staff_removal?(nomination)
        current_principal.discord_user? && !own?(nomination.user_id)
      end

      def valid_removal_reason?(reason)
        error = if reason.blank? then "reason_required"
        elsif reason.length > REMOVAL_REASON_MAX then "reason_too_long"
        end
        return true unless error

        render_error(error, "removing someone else's nomination needs a reason of 1 to #{REMOVAL_REASON_MAX} characters")
        false
      end

      # Payload (kind goty_nomination_deleted): { year, user_id, game_title,
      # deleted_by_user_id, reason }, captured before the delete.
      def enqueue_removal_notice(nomination, reason)
        title = nomination.game&.title
        nominator = nomination.user&.username.presence || nomination.user_id
        BotJob.enqueue!(
          kind: "goty_nomination_deleted",
          summary: %(Announce that #{nominator}'s GOTY Vote #{nomination.year} Game of the Year nomination ) +
            %("#{title}" was removed),
          payload: {
            year: nomination.year, user_id: nomination.user_id, game_title: title,
            deleted_by_user_id: current_principal.id.to_s, reason: reason
          },
          requested_by: current_principal.id
        )
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
