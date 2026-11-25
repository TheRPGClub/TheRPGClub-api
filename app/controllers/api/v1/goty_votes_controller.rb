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
        render_collection(GotyVote.includes(winners: { game: :images }), resource: GotyVoteSummaryResource, default_order: { year: :desc })
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
        attrs = request_data.slice(*UPDATE_ATTRS).transform_values { |value| parse_time(value) }
        unreadable = attrs.select { |_key, time| time.nil? }.keys
        if unreadable.any?
          return render_error("invalid_date",
            "#{unreadable.join(' and ')} must be a date and time, e.g. 2027-01-15T17:00:00Z")
        end
        error = update_refusal(vote, attrs)
        return render_error(*error) if error

        vote.update!(attrs)
        render_vote(vote)
      end

      # POST /api/v1/goty_votes/:year/awards/:award/resolve_tie { data: { gamedb_game_id } }
      # Queues the goty_decided post once the pick decides the vote.
      def resolve_tie
        vote = GotyVote.find(params[:year])
        picks = game_ids(params.require(:data)[:gamedb_game_id])
        return render_error("invalid_pick", "gamedb_game_id must be a game id") if picks.nil?

        Goty::Decide.resolve_tie!(vote, award: params[:award],
          gamedb_game_id: picks) { |record| Goty::AdvanceVotes.queue_decided(record) }
        render_vote(vote.reload)
      rescue Voting::Decide::NoTieError => error
        render_error("no_tie", error.message)
      rescue Voting::Decide::InvalidPickError => error
        render_error("invalid_pick", error.message)
      end

      # GET /api/v1/games/:id/goty_eligibility?year=: whether the game may be
      # nominated for that year's Game of the Year, and why not.
      def eligibility
        year = year_param or return
        game = GamedbGame.find(params[:id])
        render json: { data: eligibility_json(Goty::Eligibility.check(game, year)) }
      end

      # Most games one batch eligibility read answers.
      ELIGIBILITY_BATCH_CAP = 50

      # GET /api/v1/games/goty_eligibility?year=&game_ids=1,2,3: the same
      # answer for many games in a fixed number of queries (bot autocomplete,
      # website search). In the order given; unknown ids are left out.
      def eligibilities
        year = year_param or return
        ids = eligibility_game_ids or return
        known = GamedbGame.where(game_id: ids).pluck(:game_id).to_set
        results = Goty::Eligibility.check_all(ids.select { |id| known.include?(id) }, year)
        render json: { data: results.values.map { |result| eligibility_json(result) } }
      end

      private

      def eligibility_json(result)
        { game_id: result.game_id, year: result.year, eligible: result.eligible?, reason: result.reason,
          released_on: result.released_on&.iso8601, date_precision: result.date_precision, source: result.source }
      end

      # The required ?game_ids= (comma separated, or repeated), first
      # occurrence first; nil after rendering 422 when one is not a whole
      # number or there are more than the cap.
      def eligibility_game_ids
        raw = Array(params.require(:game_ids)).flat_map { |value| value.to_s.split(",") }.map(&:strip)
        if raw.size > ELIGIBILITY_BATCH_CAP
          render_error("too_many_game_ids", "game_ids holds at most #{ELIGIBILITY_BATCH_CAP} ids")
          return
        end
        ids = game_ids(raw)
        return ids.uniq if ids

        render_error("invalid_game_ids", "game_ids must be whole numbers separated by commas, e.g. 1,2,3")
        nil
      end

      def render_vote(vote)
        staff = admin_or_service?
        viewer = staff && params[:user_id].present? ? params[:user_id].to_s : requester_id
        render json: { data: GotyVoteResource.new(vote, params: { viewer_id: viewer, staff: staff }).serializable_hash }
      end

      # [code, message] when the dates (parsed times) may not move, else nil.
      # The opening dates are fixed once voting opens (the nominations and
      # candidates are in), the nominations' open once they opened (moving
      # it later would put the vote back to upcoming), and the close once
      # the main vote was tallied (votes cast after it would never count).
      def update_refusal(vote, attrs)
        return [ "goty_vote_decided", "GOTY Vote #{vote.year} is already decided" ] if vote.decided_at.present?

        now = Time.current
        moving = attrs.select { |key, time| time != vote[key] }.keys
        opening = moving & OPENING_ATTRS
        if opening.any? && now >= vote.voting_opens_at
          return [ "voting_opened",
            "voting for GOTY Vote #{vote.year} has opened, so #{opening.join(' and ')} can't move" ]
        end
        if moving.include?("nominations_open_at") && now >= vote.nominations_open_at
          return [ "nominations_opened",
            "nominations for GOTY Vote #{vote.year} have opened, so nominations_open_at can't move" ]
        end
        return unless moving.include?("voting_closes_at") && vote.closed_at.present?

        [ "voting_closed",
          "voting for GOTY Vote #{vote.year} closed at #{vote.closed_at.iso8601}, so voting_closes_at can't move" ]
      end

      # nil for a missing or unreadable value.
      def parse_time(value)
        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      # The picked game ids (one, or a list), or nil unless each is a whole number.
      def game_ids(value)
        ids = (value.is_a?(Array) ? value : [ value ]).map { |id| Integer(id.to_s, 10, exception: false) }
        ids unless ids.empty? || ids.include?(nil)
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
