# frozen_string_literal: true

module Api
  module V1
    # Game key giveaway (bot parity, #42): donors offer keys, users claim them.
    #
    # The `key_value` secret is never returned by the list endpoints; it is
    # revealed only to the claimer in the response to a successful claim (see
    # GameKeyResource's conditional `key_value`). Claiming locks the key row
    # (SELECT ... FOR UPDATE), so two concurrent claims on the same key cannot
    # both win: the second sees it claimed and gets 409.
    #
    # Web parity 2: claiming needs the Members role, as in the bot. A
    # member's donate, claim and revoke queue a `giveaway_hub_refresh` bot
    # job, and a claim also queues `giveaway_claim_notice` (DM the key, log
    # the claim, notify the donor). The service token's own actions queue
    # nothing: the bot already does that Discord work in-process.
    class GameKeysController < ApplicationController
      HUB_REFRESH_VERBS = { "donate" => "donated", "claim" => "claimed", "revoke" => "revoked" }.freeze

      before_action :require_owner!, only: :create
      before_action :require_member_role!, only: :claim
      before_action :require_key_reader!, only: :show
      before_action :require_donor_or_admin!, only: :destroy
      before_action :require_claimer_or_admin!, only: :claimed_index

      # GET /api/v1/game_keys
      # The available (unclaimed) keys, ordered like the bot's listing
      # (case-insensitive title, then key_id). Ordered by `game_title` (always
      # present) rather than the linked game so unlinked keys are still listed;
      # the linked game (with images) is preloaded so the embedded card resolves
      # without an N+1.
      def index
        render_collection(RpgClubGameKey.available.preload(game: :images), resource: GameKeyResource,
          default_order: Arel.sql("UPPER(game_title) ASC, key_id ASC"))
      end

      # GET /api/v1/users/:user_id/game_keys
      # Keys donated by the user, newest first.
      def user_index
        scope = RpgClubGameKey.where(donor_user_id: params[:user_id]).preload(game: :images)
        render_collection(scope, resource: GameKeyResource,
          default_order: { created_at: :desc, key_id: :desc })
      end

      # GET /api/v1/users/:user_id/claimed_game_keys
      # Keys the user claimed, newest claim first, so a claimer can find their
      # keys again. Readable by the claimer, Admin and above, and the service;
      # the secret `key_value` is included only for the claimer themselves.
      def claimed_index
        scope = RpgClubGameKey.where(claimed_by_user_id: @claimer.user_id).preload(game: :images)
        render_collection(scope, resource: GameKeyResource, params: { reveal_key: viewer_is_claimer? },
          default_order: { claimed_at: :desc, key_id: :desc })
      end

      # POST /api/v1/game_keys
      # Donate a key. Owner-only: a Discord caller may only donate as themselves
      # (`donor_user_id` must be their own id); the bot's service token may
      # donate on anyone's behalf. Pass `gamedb_game_id` to link the key to a
      # game (so the API can embed its cover/art); `game_title` is backfilled
      # from that game when omitted. `region` defaults to Global.
      def create
        record = RpgClubGameKey.transaction do
          RpgClubGameKey.create!(donate_data).tap { |key| enqueue_hub_refresh("donate", key) }
        end
        record.reload
        render json: { data: GameKeyResource.new(record).serializable_hash }, status: :created
      end

      # GET /api/v1/game_keys/:id
      # A single key with its secret `key_value` revealed. Unlike the listing
      # endpoints (which always withhold the secret), this exposes it — so it is
      # restricted to those entitled to the key: the service token, the donor, an
      # admin, or the user who has claimed it (see require_key_reader!). An
      # unclaimed key has no claimer to match, so it can't be read out-of-band to
      # bypass the claim flow.
      def show
        render json: { data: GameKeyResource.new(game_key, params: { reveal_key: true }).serializable_hash }
      end

      # DELETE /api/v1/game_keys/:id
      # Revoke (delete) a key. Authorized for the original donor, an admin, or
      # the service token (see require_donor_or_admin!).
      def destroy
        RpgClubGameKey.transaction do
          game_key.destroy!
          enqueue_hub_refresh("revoke", game_key)
        end
        render json: { deleted: true }
      end

      # POST /api/v1/game_keys/:id/claim
      # Atomically claim an unclaimed key and reveal its `key_value` to the
      # claimer. A Discord caller claims as themselves; the service token claims
      # on behalf of the `claimed_by_user_id` it supplies.
      def claim
        claimant_id = resolve_claimant_id
        return render json: { error: "claimant_required" }, status: :unprocessable_entity if claimant_id.blank?

        notice = nil
        claimed = RpgClubGameKey.transaction do
          key = RpgClubGameKey.lock.find(params[:id])
          next false if key.claimed_by_user_id.present?

          now = Time.current
          key.update_columns(claimed_by_user_id: claimant_id, claimed_at: now, updated_at: now)
          notice = enqueue_claim_notice(key)
          enqueue_hub_refresh("claim", key)
          true
        end
        return render json: { error: "already_claimed" }, status: :conflict unless claimed

        record = RpgClubGameKey.includes(game: :images).find(params[:id])
        render json: { data: GameKeyResource.new(record, params: { reveal_key: true }).serializable_hash,
                       meta: { claim_notice_job_id: notice&.id } }
      end

      private

      # The key targeted by the member routes (show/destroy), with its linked
      # game and images preloaded for the embedded card. Memoized so the
      # authorization before_action and the action share a single lookup. A
      # missing key raises RecordNotFound (404) before any authz check runs.
      def game_key
        @game_key ||= RpgClubGameKey.includes(game: :images).find(params[:id])
      end

      # show reveals the secret, so it's limited to those entitled to the key:
      # the service token, the donor, an admin, or the user who has claimed it. A
      # claimer reading their own claimed key isn't a bypass — they already own
      # it — while an unclaimed key has no claimer to match, so it stays locked
      # to donor/admin/service. The listing endpoints, which never expose the
      # secret, remain open reads.
      def require_key_reader!
        return true if donor_admin_or_service?
        if current_principal&.discord_user? &&
            current_principal.id.to_s == game_key.claimed_by_user_id.to_s
          return true
        end

        forbidden!
      end

      # destroy (revoke) is limited to the original donor, an admin, or the
      # service token — the audience the issue specifies for revocation. The
      # claimer is deliberately excluded (they receive the key, not control over
      # the donation).
      def require_donor_or_admin!
        return true if donor_admin_or_service?

        forbidden!
      end

      # Shared predicate for the member routes: the key's donor, or
      # admin-or-above (Admin, Superadmin, the service token).
      def donor_admin_or_service?
        return true if current_principal&.discord_user? && current_principal.id.to_s == game_key.donor_user_id.to_s

        admin_or_above?
      end

      # claimed_index: an unknown user is 404 (before the role check), then
      # only the claimer, Admin and above, or the service may list.
      def require_claimer_or_admin!
        @claimer = RpgClubUser.find(params[:user_id])
        return true if viewer_is_claimer? || admin_or_above?

        forbidden!
      end

      def viewer_is_claimer?
        current_principal&.discord_user? && current_principal.id.to_s == @claimer.user_id.to_s
      end

      def forbidden!
        render json: { error: "forbidden" }, status: :forbidden
        false
      end

      # Donations set only the offer fields; the claim columns, identity and
      # timestamps are not client-writable (so a key can't be donated
      # pre-claimed or with a spoofed id/timestamp). When the donor links a game
      # but omits the title, fall back to the game's title so `game_title`
      # (the listing's sort key and the unlinked-display label) is always set.
      # A blank `region` (omitted or null) falls back to the default rather than
      # being stored as null — every key has a region.
      def donate_data
        attrs = request_data.except("key_id", "claimed_by_user_id", "claimed_at", "created_at", "updated_at")
        attrs = attrs.merge("region" => RpgClubGameKey::DEFAULT_REGION) if attrs["region"].blank?

        if attrs["game_title"].blank? && attrs["gamedb_game_id"].present?
          title = GamedbGame.where(game_id: attrs["gamedb_game_id"]).pick(:title)
          attrs = attrs.merge("game_title" => title) if title
        end

        attrs
      end

      # Who the claim is recorded against: a Discord caller can only claim for
      # themselves; the bot's service token names the user in the body.
      def resolve_claimant_id
        return current_principal.id if current_principal&.discord_user?

        params.dig(:data, :claimed_by_user_id).presence
      end

      # Discord work for the bot when a member acted from a client other than
      # the bot. Called inside the write's transaction, so a failed write
      # queues nothing.
      def member_action?
        current_principal&.discord_user?
      end

      # Payload: `{ reason: "donate"|"claim"|"revoke", key_id }`.
      def enqueue_hub_refresh(reason, key)
        return unless member_action?

        BotJob.enqueue!(kind: "giveaway_hub_refresh", payload: { reason: reason, key_id: key.key_id },
          summary: "Refresh the giveaway hub: #{key_label(key)} #{HUB_REFRESH_VERBS.fetch(reason)}",
          requested_by: current_principal.id)
      end

      # "Chrono Cross (PSN)": the title and platform only, never the key.
      def key_label(key)
        "#{key.game_title} (#{key.platform})"
      end

      # Payload: ids plus the labels the claim log needs. The secret
      # `key_value` stays out of the job; the bot reads it with
      # GET /game_keys/:id.
      def enqueue_claim_notice(key)
        return unless member_action?

        BotJob.enqueue!(kind: "giveaway_claim_notice", requested_by: current_principal.id,
          summary: "DM the claimed #{key_label(key)} key, log the claim and notify the donor", payload: {
          key_id: key.key_id, claimed_by_user_id: key.claimed_by_user_id, donor_user_id: key.donor_user_id,
          game_title: key.game_title, platform: key.platform
        })
      end

      # require_owner! for #create resolves the owner from the donor named in
      # the request body.
      def resolve_owner_id
        params.dig(:data, :donor_user_id).presence
      end
    end
  end
end
