# frozen_string_literal: true

module Api
  module V1
    # GOTM / Non-RPG GOTM nominations for a voting round (bot parity, #40, #97).
    # The winners are served by gotm_entries / nr_gotm_entries; these are the
    # field of candidates behind a round, each with its nominator and game.
    #
    # Reads (the round list and a single user's nomination) are open to any
    # authenticated caller.
    #
    # Writes are owner-gated so members can nominate from the web: the service
    # token (the bot's `/nominate`) may upsert/delete for any user at any
    # time; a logged-in member only for themselves, and only while the round's
    # nomination window is open (see VotingRound.nominations_open_for? —
    # only the current round collects, until its vote opens). Admins share the
    # service exemption for fixups. The round-scoped destroy_all stays
    # admin/service-only (the `/admin delete-*-noms` reset).
    #
    # The two backing tables share an identical shape, so each public action is
    # a thin GOTM/NR-GOTM pair that delegates to a model-agnostic private
    # helper.
    class NominationsController < ApplicationController
      before_action :require_nomination_owner!, only: %i[
        create_gotm create_nr_gotm
        destroy_gotm destroy_nr_gotm
      ]
      before_action :require_nomination_window!, only: %i[
        create_gotm create_nr_gotm
        destroy_gotm destroy_nr_gotm
      ]
      before_action :require_admin_or_service!, only: %i[
        destroy_all_gotm destroy_all_nr_gotm
      ]

      # Caller-settable columns on upsert. `round_number` comes from the path and
      # `nominated_at` is a DB default, so neither is accepted in the body.
      WRITABLE_ATTRS = %w[user_id gamedb_game_id reason].freeze

      # Votes (#173) hang off nominations with no DB FK (bot-data precedent),
      # so the destroy paths below clear them by hand to avoid orphaned
      # ballots.
      VOTE_MODELS = { GotmNomination => GotmVote, NrGotmNomination => NrGotmVote }.freeze
      CATEGORIES = { GotmNomination => "gotm", NrGotmNomination => "nr_gotm" }.freeze
      # The bot's own limit on the deletion reason modal.
      REMOVAL_REASON_MAX = 250

      # GET /api/v1/gotm_entries/:round/nominations
      def gotm
        render_nominations(GotmNomination)
      end

      # GET /api/v1/nr_gotm_entries/:round/nominations
      def nr_gotm
        render_nominations(NrGotmNomination)
      end

      # GET /api/v1/gotm_entries/:round/nominations/:user_id
      def show_gotm
        render_nomination(GotmNomination)
      end

      # GET /api/v1/nr_gotm_entries/:round/nominations/:user_id
      def show_nr_gotm
        render_nomination(NrGotmNomination)
      end

      # POST /api/v1/gotm_entries/:round/nominations
      def create_gotm
        upsert_nomination(GotmNomination)
      end

      # POST /api/v1/nr_gotm_entries/:round/nominations
      def create_nr_gotm
        upsert_nomination(NrGotmNomination)
      end

      # DELETE /api/v1/gotm_entries/:round/nominations/:user_id
      def destroy_gotm
        destroy_nomination(GotmNomination)
      end

      # DELETE /api/v1/nr_gotm_entries/:round/nominations/:user_id
      def destroy_nr_gotm
        destroy_nomination(NrGotmNomination)
      end

      # DELETE /api/v1/gotm_entries/:round/nominations
      def destroy_all_gotm
        destroy_all_nominations(GotmNomination)
      end

      # DELETE /api/v1/nr_gotm_entries/:round/nominations
      def destroy_all_nr_gotm
        destroy_all_nominations(NrGotmNomination)
      end

      private

      # Nominations for the round in the path, oldest first, each carrying its
      # embedded nominator and game. Images and platforms are preloaded so the
      # game summary's cover / art / logo URLs and the board's platform pills
      # resolve in one query each rather than one per nomination.
      def render_nominations(model)
        scope = model.where(round_number: params[:round])
          .preload(:user, game: [ :images, :platforms ])

        render_collection(scope, resource: NominationResource,
          default_order: { nominated_at: :asc, nomination_id: :asc })
      end

      # A single user's nomination for the round, or 404 if they have none.
      def render_nomination(model)
        record = round_scope(model)
          .preload(:user, game: [ :images, :platforms ])
          .find_by!(user_id: params[:user_id])
        render json: { data: NominationResource.new(record).serializable_hash }
      end

      # Upsert keyed on (round_number, user_id) — a user re-nominating replaces
      # their previous entry for the round (mirrors the bot's ON CONFLICT). 201
      # when a new nomination is created, 200 when an existing one is updated.
      def upsert_nomination(model)
        data = request_data.slice(*WRITABLE_ATTRS)
        record = model.find_or_initialize_by(round_number: params[:round], user_id: data["user_id"])
        created = record.new_record?
        record.assign_attributes(data.except("user_id"))
        record.save!
        record.reload

        render json: { data: NominationResource.new(record).serializable_hash },
          status: created ? :created : :ok
      end

      # DELETE /.../:user_id — removes one user's nomination for the round,
      # along with any votes cast on it. Votes on a different nomination of
      # the same game are untouched — they reference their own nomination.
      #
      # A staff member removing someone else's nomination (#332) must give a
      # `reason`, and the bot announces the removal in the nomination channel
      # (no DM to the nominator). Owners and the service keep the plain
      # delete: the bot announces its own deletes inline.
      def destroy_nomination(model)
        record = round_scope(model).preload(:user, :game).find_by!(user_id: params[:user_id])
        reason = params[:reason].to_s.strip
        announce = staff_removal?(record)
        return if announce && !valid_removal_reason?(reason)

        model.transaction do
          VOTE_MODELS.fetch(model).where(nomination_id: record.nomination_id).delete_all
          record.destroy!
          enqueue_removal_notice(model, record, reason) if announce
        end
        render json: { deleted: true }
      end

      # A signed-in member (necessarily Admin and up, past the owner gate)
      # deleting a nomination that is not theirs.
      def staff_removal?(record)
        current_principal.discord_user? && current_principal.id.to_s != record.user_id.to_s
      end

      def valid_removal_reason?(reason)
        error = if reason.blank? then "reason_required"
        elsif reason.length > REMOVAL_REASON_MAX then "reason_too_long"
        end
        return true unless error

        render json: {
          error: error,
          message: "removing someone else's nomination needs a reason of 1 to #{REMOVAL_REASON_MAX} characters"
        }, status: :unprocessable_entity
        false
      end

      # Payload (kind nomination_deleted): { category, round_number, user_id,
      # game_title, deleted_by_user_id, reason }, captured before the delete.
      # game_title is null for a GOTM nomination without a game.
      def enqueue_removal_notice(model, record, reason)
        category = CATEGORIES.fetch(model)
        title = record.game&.title
        nominator = record.user&.username.presence || record.user_id
        game = title ? %( "#{title}") : ""
        summary = "Announce that #{nominator}'s #{Gotm::RoundCreate.label(category)} round " \
          "#{record.round_number} nomination#{game} was removed"

        BotJob.enqueue!(
          kind: "nomination_deleted",
          summary: summary,
          payload: {
            category: category, round_number: record.round_number, user_id: record.user_id,
            game_title: title, deleted_by_user_id: current_principal.id.to_s, reason: reason
          },
          requested_by: current_principal.id
        )
      end

      # DELETE /.../nominations — clears every nomination for the round (the
      # `/admin delete-*-noms` reset before a voting round opens), along with
      # the round's votes. Always scoped to the round in the path, so the
      # whole tables can never be wiped.
      def destroy_all_nominations(model)
        count = nil
        model.transaction do
          VOTE_MODELS.fetch(model).where(round_number: params[:round]).delete_all
          count = round_scope(model).delete_all
        end
        render json: { deleted: true, count: count }
      end

      def round_scope(model)
        model.where(round_number: params[:round])
      end

      # Owner-or-admin gate for the single-nomination writes: the service
      # token and admins act for any user, a member only for themselves. The
      # owner id comes from the body on upsert and the path on delete.
      def require_nomination_owner!
        return true if admin_or_service?
        return true if current_principal&.discord_user? &&
          resolve_owner_id.present? &&
          current_principal.id.to_s == resolve_owner_id.to_s

        render json: { error: "forbidden" }, status: :forbidden
        false
      end

      def resolve_owner_id
        action_name.start_with?("destroy") ? params[:user_id] : params.dig(:data, :user_id).presence
      end

      # Members may only write while the round's nomination window is open.
      # Service/admin bypass it: the bot enforces its own window and admins
      # need out-of-band fixups (mirrors the votes reset precedent).
      def require_nomination_window!
        return true if admin_or_service?
        return true if VotingRound.nominations_open_for?(params[:round])

        render json: {
          error: "nominations_closed",
          message: "nominations for round #{params[:round]} are not open"
        }, status: :unprocessable_entity
        false
      end
    end
  end
end
