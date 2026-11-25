# frozen_string_literal: true

module Api
  module V1
    class CompletionsController < ApplicationController
      include GameIdFilter
      include CodedRefusals
      include ShelfPlaytime

      feature :game_completions

      # The date checks a create or update can be refused with (422 `error`).
      DATE_REFUSALS = %i[finished_in_future started_after_finished started_in_future].freeze

      before_action :require_owner!, only: %i[export update destroy]
      # A Superadmin may also log a Game Completion for another member (the
      # bot's Superadmin completion command).
      before_action :require_owner_or_superadmin!, only: :create

      # Caller-settable columns. `user_id` comes from the path (or the existing
      # record) and the key is generated, so neither is accepted in the body.
      WRITABLE_ATTRS = %w[gamedb_game_id platform_id completion_type started_at completed_at final_playtime_hrs
                          note].freeze

      def index
        scope = filtered_completions(UserGameCompletion.where(user_id: params[:user_id]))
        render_shelf(scope.preload(:game, :platform), resource: CompletionEntryResource,
          default_order: { completed_at: :desc, created_at: :desc })
      end

      # Games both members completed (`:user_id` on the left, `other_user_id`
      # on the right). See Completions::Common for the filter/sort semantics.
      # A grouped query, so the count is computed explicitly for pagy (as in
      # `leaderboard`).
      def common
        other_user_id = params[:other_user_id].presence
        return render(json: { error: "other_user_id is required" }, status: :unprocessable_content) unless other_user_id
        if other_user_id.to_s == params[:user_id].to_s
          return render(json: { error: "other_user_id must be a different member" }, status: :unprocessable_content)
        end
        return if invalid_common_param?

        left = RpgClubUser.find(params[:user_id])
        right = RpgClubUser.find(other_user_id)
        query = Completions::Common.new(
          left_user_id: left.user_id, right_user_id: right.user_id,
          **params.permit(:year, :platform_id, :q, :sort).to_h.symbolize_keys
        )

        pagy, page = pagy(query.relation, count: query.count, **pagy_options)
        render json: {
          data: CommonCompletionEntryResource.new(query.rows(page)).serializable_hash,
          meta: pagy_meta(pagy).merge(left_user_id: left.user_id, right_user_id: right.user_id)
        }
      rescue Completions::Common::InvalidSort => e
        render json: { error: e.message }, status: :unprocessable_content
      end

      # Every one of the user's completions as a CSV download, in the bot's
      # export format (see Completions::CsvExport). Owner-only, like the bot's
      # self-only `/game-completion export`, even though the JSON index is open.
      # Unpaginated, in the index's order.
      def export
        completions = UserGameCompletion.where(user_id: params[:user_id]).includes(:game)
          .order(completed_at: :desc, created_at: :desc)
        send_data Completions::CsvExport.new(completions).to_csv,
          type: "text/csv; charset=utf-8", disposition: "attachment", filename: "completions.csv"
      end

      def game_index
        scope = UserGameCompletion.where(gamedb_game_id: params[:id]).includes(:user)
        render_collection(scope, resource: CompletionUserEntryResource, default_order: { completed_at: :desc })
      end

      # Users ranked by total completion count (most first). Mirrors the bot's
      # `getCompletionLeaderboard`: active members only (`server_left_at IS
      # NULL`), with an optional `q` filter on game title. Paginated with the
      # standard page/per params. A grouped aggregate, so the count is computed
      # explicitly and handed to pagy (its grouped-count path would otherwise
      # collide with the `COUNT(*)` ordering).
      def leaderboard
        base = RpgClubUser.where(server_left_at: nil).joins(:game_completions)
        if params[:q].present?
          base = base.joins(game_completions: :game)
            .where("gamedb_games.title ILIKE ?", "%#{sanitize_like(params[:q])}%")
        end

        count = base.distinct.count(:user_id)
        ranked = base
          .group("rpg_club_users.user_id", "rpg_club_users.username", "rpg_club_users.global_name")
          .select(
            "rpg_club_users.user_id AS user_id",
            "rpg_club_users.username AS username",
            "rpg_club_users.global_name AS global_name",
            "COUNT(user_game_completions.completion_id) AS completion_count"
          )
          .order(Arel.sql("COUNT(user_game_completions.completion_id) DESC, rpg_club_users.user_id ASC"))

        pagy, records = pagy(ranked, count: count, **pagy_options)
        render json: {
          data: CompletionLeaderboardEntryResource.new(records).serializable_hash,
          meta: pagy_meta(pagy)
        }
      end

      # GET /api/v1/completions/recent
      #
      # Every member's Game Completions, newest first, for the club Recent
      # Completions Dashboard Panel. "Newest" is `completed_at` (so a backdated
      # import doesn't read as recent), undated ones last, then the time they
      # were logged. Members who have left the server are left out.
      def recent
        scope = UserGameCompletion.joins(:user).where(rpg_club_users: { server_left_at: nil })
          .preload(:user, :platform, game: :images)
        render_collection(scope, resource: CompletionMemberEntryResource,
          default_order: Arel.sql("user_game_completions.completed_at DESC NULLS LAST, " \
                                  "user_game_completions.created_at DESC, user_game_completions.completion_id DESC"))
      end

      def show
        record = UserGameCompletion.includes(:game, :platform).find(params[:id])
        render json: { data: CompletionEntryResource.new(record).serializable_hash }
      end

      # `data.announce` (optional boolean) queues `completion_announce` so the
      # bot posts it to the completions channel; `meta.announce_job_id` is that
      # job (null when none was queued). `data.leave_now_playing` (optional
      # boolean) takes the game off the member's Now Playing in the same
      # transaction; when a Superadmin logs one for another member that always
      # happens, as the bot does. `meta.left_now_playing` says whether an entry
      # was removed. The member's open Playthrough of the game closes with
      # it, and an empty `final_playtime_hrs` takes its time (spec api#457).
      def create
        announce = request_data["announce"]
        leave_now_playing = request_data["leave_now_playing"]
        { "announce" => announce, "leave_now_playing" => leave_now_playing }.each do |name, value|
          next if [ nil, true, false ].include?(value)

          return render(json: { error: "#{name} must be a boolean" }, status: :unprocessable_content)
        end

        RpgClubUser.find(params[:user_id]) if logged_for_another_member?

        record, announce_job, left = UserGameCompletion.transaction do
          completion = UserGameCompletion.create!(writable_data.merge("user_id" => params[:user_id]))
          Playtime::Playthroughs.close_for_completion!(completion)
          removed =
            if leave_now_playing || logged_for_another_member?
              # Skips callbacks; the completion's own commit refreshes the
              # member's Runs (Challenges::CountsTowardRuns) after this too.
              UserNowPlaying.where(user_id: completion.user_id, gamedb_game_id: completion.gamedb_game_id).delete_all
            else
              0
            end
          [ completion, (enqueue_announce(completion) if announce), removed.positive? ]
        end
        check_conquests(record)
        record.reload
        render json: { data: CompletionEntryResource.new(record).serializable_hash,
                       meta: { announce_job_id: announce_job&.id, left_now_playing: left } }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_coded_refusal(e, DATE_REFUSALS)
      end

      def update
        record = UserGameCompletion.find(params[:id])
        record.update!(writable_data)
        check_conquests(record)
        record.reload
        render json: { data: CompletionEntryResource.new(record).serializable_hash }
      rescue ActiveRecord::RecordInvalid => e
        render_coded_refusal(e, DATE_REFUSALS)
      end

      def destroy
        UserGameCompletion.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      def require_owner_or_superadmin!
        return true if current_principal&.discord_user? && superadmin?

        require_owner!
      end

      # A signed-in member logging a completion under someone else's id (only
      # a Superadmin gets past the gate to do that).
      def logged_for_another_member?
        current_principal&.discord_user? && current_principal.id.to_s != params[:user_id].to_s
      end

      # Franchise Progress (spec api#457): a Completion may finish a
      # Franchise's Mainline set. The Conquest is announced whether or not
      # the Completion was.
      def check_conquests(completion)
        Franchises::ConquestCheck.new(requested_by: requester_id).after_completion(completion)
      end

      def enqueue_announce(completion)
        actor_id = requester_id
        member = completion.user
        name = member&.global_name.presence || member&.username.presence || completion.user_id
        BotJob.enqueue!(
          kind: "completion_announce",
          summary: %(Announce #{name}'s Game Completion of "#{completion.game&.title}"),
          payload: {
            completion_id: completion.completion_id, user_id: completion.user_id,
            game_id: completion.gamedb_game_id, actor_user_id: actor_id
          },
          requested_by: actor_id
        )
      end

      def writable_data
        request_data.slice(*WRITABLE_ATTRS)
      end

      # Optional filters on a user's completions list, mirroring the bot's
      # `getCompletions` / `countCompletions` / `getCompletionsForGame` /
      # `getRecentCompletionForGame` (#102). Each present param ANDs in; the `q`
      # title match goes through a `gamedb_game_id` subquery (no join) so the
      # paginated `meta.count` stays exact — the bot reads that count (with
      # `per=1`) in place of `countCompletions`.
      #
      # - `game_id`        exact `gamedb_game_id`
      # - `platform_id`    exact `platform_id`
      # - `year`           completion year via `EXTRACT(YEAR FROM completed_at)`;
      #                    the literal `unknown` matches rows with no
      #                    `completed_at` (the bot's `year: "unknown"` case)
      # - `q`              case-insensitive game-title substring
      # - `completed_after` / `completed_before`  inclusive `completed_at` range
      #                    (a date-only value covers that whole club day)
      def filtered_completions(scope)
        scope = by_game(scope)
        scope = scope.where(platform_id: params[:platform_id]) if params[:platform_id].present?

        if params[:year].present?
          scope =
            if params[:year].to_s.casecmp?("unknown")
              scope.where(completed_at: nil)
            else
              scope.where("EXTRACT(YEAR FROM completed_at) = ?", params[:year].to_i)
            end
        end

        if params[:q].present?
          titles = GamedbGame.where("title ILIKE ?", "%#{sanitize_like(params[:q])}%").select(:game_id)
          scope = scope.where(gamedb_game_id: titles)
        end

        if params[:completed_after].present?
          scope = scope.where("completed_at >= ?", range_bound(params[:completed_after], :beginning_of_day))
        end
        if params[:completed_before].present?
          scope = scope.where("completed_at <= ?", range_bound(params[:completed_before], :end_of_day))
        end
        scope
      end

      # A date-only `completed_after` / `completed_before` is a whole club day
      # (completion days are stored at noon club time); a timestamp is a moment.
      def range_bound(value, edge)
        text = value.to_s.strip
        return value unless ClubDay::DATE_ONLY.match?(text)

        Date.iso8601(text).in_time_zone(ClubDay::TIME_ZONE).public_send(edge)
      rescue Date::Error
        value
      end

      # Renders 422 `invalid_year` / `invalid_platform_id` (the gotm_rounds
      # shape) for a `common` filter that isn't an integer (`year` may also be
      # `unknown`).
      def invalid_common_param?
        year = params[:year].presence
        if year && !year.to_s.casecmp?("unknown") && Integer(year.to_s, 10, exception: false).nil?
          render json: { error: "invalid_year", message: "year must be an integer or unknown" }, status: :unprocessable_content
        elsif params[:platform_id].present? && Integer(params[:platform_id].to_s, 10, exception: false).nil?
          render json: { error: "invalid_platform_id", message: "platform_id must be an integer" }, status: :unprocessable_content
        end
        performed?
      end

      def sanitize_like(value)
        ActiveRecord::Base.sanitize_sql_like(value.to_s.strip)
      end

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        UserGameCompletion.find_by(completion_id: params[:id])&.user_id
      end
    end
  end
end
