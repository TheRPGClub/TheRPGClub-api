# frozen_string_literal: true

module Api
  module V1
    # The GOTM / NR-GOTM round lifecycle, owned here (see VotingRound). Reads
    # are open to any authenticated caller; rescheduling and tie-breaking are
    # admin/service. Nothing creates rounds by hand: deciding a round schedules
    # the next one.
    class VotingRoundsController < ApplicationController
      before_action :require_admin_or_service!, only: %i[update resolve_tie publish_results repost_panels]

      # Rescheduling fields. Moving the open without a close keeps the default
      # weekend window; "close voting now" is `voting_closes_at: <now>`.
      UPDATE_ATTRS = %w[voting_opens_at voting_closes_at month_year].freeze
      CATEGORY_LABELS = { "gotm" => "GOTM", "nr_gotm" => "NR-GOTM" }.freeze

      def index
        render_collection(VotingRound.all, resource: VotingRoundResource, default_order: { round_number: :desc })
      end

      # GET /api/v1/voting_rounds/current — the one round being nominated for,
      # voted on or awaiting its decision.
      def current
        round = VotingRound.current or raise ActiveRecord::RecordNotFound, "no voting round is scheduled"
        render_round(round)
      end

      def show
        render_round(VotingRound.find(params[:id]))
      end

      def update
        round = VotingRound.find(params[:id])
        if round.decided_at.present?
          return render json: { error: "round_decided", message: "round #{round.round_number} is already decided" },
            status: :unprocessable_entity
        end

        attrs = request_data.slice(*UPDATE_ATTRS)
        closing = closes_now?(attrs["voting_closes_at"])
        if closing && !round.voting_open?
          return render json: { error: "voting_not_open", message: "voting for round #{round.round_number} is not open" },
            status: :unprocessable_entity
        end

        VotingRound.transaction do
          round.update!(attrs)
          queue_poll_wakeup!(round, closing ? "voting on round #{round.round_number} was closed" :
            "round #{round.round_number} was rescheduled")
        end
        render_round(round)
      end

      # POST /api/v1/voting_rounds/:id/resolve_tie { data: { category, gamedb_game_ids } }
      def resolve_tie
        data = request_data
        round = VotingRound.transaction do
          resolved = Voting::ResolveTie.new(
            VotingRound.find(params[:id]),
            category: data["category"],
            gamedb_game_ids: data["gamedb_game_ids"]
          ).call
          queue_tie_broken!(resolved, data["category"].to_s, data["gamedb_game_ids"])
          resolved
        end
        render_round(round)
      rescue Voting::ResolveTie::NoTieError => error
        render json: { error: "no_tie", message: error.message }, status: :unprocessable_entity
      rescue Voting::ResolveTie::InvalidPickError => error
        render json: { error: "invalid_pick", message: error.message }, status: :unprocessable_entity
      end

      # POST /api/v1/voting_rounds/:id/publish_results: the manual results
      # post (and winner thread), once voting has ended. Repeatable, so a
      # Discord failure can be retried. Works whatever the automation flag
      # says. A round from before voting_rounds existed takes its month from
      # its GOTM entries.
      def publish_results
        number = params[:id].to_i
        round = VotingRound.find_by(round_number: number)
        month = round&.month_year || GotmEntry.where(round_number: number).pick(:month_year)
        raise ActiveRecord::RecordNotFound, "no voting round or GOTM entry for round #{number}" if month.blank?

        unless VotingRound.ended?(number)
          return render json: { error: "voting_not_ended", message: "voting for round #{number} has not ended" },
            status: :unprocessable_entity
        end

        render_job BotJob.enqueue!(kind: "voting_results_publish",
          summary: "Publish the results of round #{number} (#{month})",
          payload: { round_number: number, month_label: month }, requested_by: requester_id)
      end

      # POST /api/v1/voting_rounds/current/repost_panels: posts the voting
      # panels again, while voting is open. Works whatever the automation
      # flag says.
      def repost_panels
        round = VotingRound.current or raise ActiveRecord::RecordNotFound, "no voting round is scheduled"
        unless round.voting_open?
          return render json: { error: "voting_not_open", message: "voting for round #{round.round_number} is not open" },
            status: :unprocessable_entity
        end

        render_job BotJob.enqueue!(kind: "voting_panels_repost",
          summary: "Repost the voting panels for round #{round.round_number}",
          payload: { round_number: round.round_number }, requested_by: requester_id)
      end

      private

      # 202: the bot carries the job out; poll GET /bot_jobs/:id for its outcome.
      def render_job(job)
        render json: { data: BotJobResource.new(job).serializable_hash }, status: :accepted
      end

      # "Close voting now" is a close moved to the present (or the past).
      def closes_now?(value)
        return false if value.blank?

        at = Time.zone.parse(value.to_s)
        at.present? && at <= Time.current
      rescue ArgumentError
        false
      end

      # The bot's voting poller sleeps until the API's next_poll_at (up to an
      # hour); a staff change to a round wakes it so panels and results go out
      # now. The bot's handler takes no payload.
      def queue_poll_wakeup!(round, what)
        BotJob.enqueue!(kind: "voting_poll_wakeup", summary: "Wake the voting poller: #{what}", payload: {},
          requested_by: requester_id)
      end

      # Tells Discord who won the tie (the bot's announceTieBreak), then wakes
      # the poller for the round_decided event a last tie leaves behind.
      def queue_tie_broken!(round, category, game_ids)
        label = CATEGORY_LABELS.fetch(category)
        games = GamedbGame.where(game_id: Array(game_ids).map(&:to_i)).order(:game_id)
          .map { |game| { game_id: game.game_id, title: game.title } }
        BotJob.enqueue!(kind: "voting_tie_broken",
          summary: "Announce the #{label} tie break for round #{round.round_number}: " \
                   "#{games.map { |game| game[:title] }.join(', ')}",
          payload: { round_number: round.round_number, category: category, games: games },
          requested_by: requester_id)
        queue_poll_wakeup!(round, "the #{label} tie for round #{round.round_number} was broken")
      end

      # The acting member, so the job shows in their activity list; nil for
      # the service.
      def requester_id
        current_principal.discord_user? ? current_principal.id : nil
      end

      def render_round(round)
        render json: { data: VotingRoundResource.new(round).serializable_hash }
      end
    end
  end
end
