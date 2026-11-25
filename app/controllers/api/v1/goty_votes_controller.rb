# frozen_string_literal: true

module Api
  module V1
    # The yearly GOTY Vote (spec api#471). Reads are open to any caller who
    # can use the Feature; nothing creates a GOTY Vote by hand (the lifecycle
    # sweep does, with the default schedule). Admins move its dates and
    # settle a tie a runoff left (api#474).
    class GotyVotesController < ApplicationController
      feature :goty_vote

      before_action :require_admin_or_service!, only: %i[update resolve_tie]

      # Movable dates. Moving the voting open without a close keeps the
      # default weekend window; "close voting now" is `voting_closes_at: <now>`.
      UPDATE_ATTRS = %w[nominations_open_at voting_opens_at voting_closes_at].freeze
      # Fixed once voting has opened: the nominations and candidates are in.
      OPENING_ATTRS = %w[nominations_open_at voting_opens_at].freeze

      def index
        render_collection(GotyVote.all, resource: GotyVoteSummaryResource, default_order: { year: :desc })
      end

      # GET /api/v1/goty_votes/:year[?user_id=]: the Awards show the
      # signed-in member's own votes; staff and the service may name another
      # member in `user_id` (the bot's vote panels).
      def show
        render_vote(GotyVote.find(params[:year]))
      end

      # PATCH /api/v1/goty_votes/:year { data: { nominations_open_at, voting_opens_at, voting_closes_at } }
      def update
        vote = GotyVote.find(params[:year])
        attrs = request_data.slice(*UPDATE_ATTRS)
        error = update_refusal(vote, attrs)
        return render_error(*error) if error

        vote.update!(attrs)
        render_vote(vote)
      end

      # POST /api/v1/goty_votes/:year/awards/:award/resolve_tie { data: { gamedb_game_id } }
      # Queues the goty_decided post once the pick decides the vote.
      def resolve_tie
        vote = GotyVote.find(params[:year])
        Goty::Decide.resolve_tie!(vote, award: params[:award],
          gamedb_game_id: params.require(:data)[:gamedb_game_id]) { |record| Goty::AdvanceVotes.queue_decided(record) }
        render_vote(vote.reload)
      rescue Voting::Decide::NoTieError => error
        render_error("no_tie", error.message)
      rescue Voting::Decide::InvalidPickError, ArgumentError, TypeError => error
        render_error("invalid_pick", error.message)
      end

      # GET /api/v1/games/:id/goty_eligibility?year=: whether the game may be
      # nominated for that year's Game of the Year, and why not.
      def eligibility
        year = year_param or return
        game = GamedbGame.find(params[:id])
        result = Goty::Eligibility.check(game, year)
        render json: { data: {
          game_id: result.game_id, year: result.year, eligible: result.eligible?, reason: result.reason,
          released_on: result.released_on&.iso8601, date_precision: result.date_precision, source: result.source
        } }
      end

      private

      def render_vote(vote)
        staff = admin_or_service?
        viewer = staff && params[:user_id].present? ? params[:user_id].to_s : requester_id
        render json: { data: GotyVoteResource.new(vote, params: { viewer_id: viewer, staff: staff }).serializable_hash }
      end

      # [code, message] when the dates may not move, else nil.
      def update_refusal(vote, attrs)
        return [ "goty_vote_decided", "GOTY Vote #{vote.year} is already decided" ] if vote.decided_at.present?

        moving = OPENING_ATTRS.select { |key| attrs.key?(key) && parse_time(attrs[key]) != vote[key] }
        return if moving.empty? || Time.current < vote.voting_opens_at

        [ "voting_opened", "voting for GOTY Vote #{vote.year} has opened, so #{moving.join(' and ')} can't move" ]
      end

      def parse_time(value)
        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def render_error(code, message)
        render json: { error: code, message: message }, status: :unprocessable_content
      end

      # The required ?year=, or nil after rendering 400.
      def year_param
        Integer(params.require(:year), 10)
      rescue ArgumentError
        render json: { error: "year must be a year, e.g. 2026" }, status: :bad_request
        nil
      end
    end
  end
end
