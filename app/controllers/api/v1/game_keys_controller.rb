# frozen_string_literal: true

module Api
  module V1
    # Game key giveaway (bot parity, #42): donors offer keys, users claim them.
    #
    # The `key_value` secret is never returned by the list endpoints; it is
    # revealed only to the claimer in the response to a successful claim (see
    # GameKeyResource's conditional `key_value`). Claiming is atomic — the
    # UPDATE is guarded by `claimed_by_user_id IS NULL`, so two concurrent
    # claims on the same key cannot both win.
    class GameKeysController < ApplicationController
      before_action :require_owner!, only: :create
      before_action :require_donor_or_admin!, only: %i[show destroy]

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

      # POST /api/v1/game_keys
      # Donate a key. Owner-only: a Discord caller may only donate as themselves
      # (`donor_user_id` must be their own id); the bot's service token may
      # donate on anyone's behalf. Pass `gamedb_game_id` to link the key to a
      # game (so the API can embed its cover/art); `game_title` is backfilled
      # from that game when omitted.
      def create
        record = RpgClubGameKey.create!(donate_data)
        record.reload
        render json: { data: GameKeyResource.new(record).serializable_hash }, status: :created
      end

      # GET /api/v1/game_keys/:id
      # A single key with its secret `key_value` revealed. Unlike the listing
      # endpoints (which always withhold the secret), this exposes it — so it is
      # restricted to the key's donor, an admin, or the service token, ensuring a
      # key can't be read out-of-band to bypass the claim flow.
      def show
        render json: { data: GameKeyResource.new(game_key, params: { reveal_key: true }).serializable_hash }
      end

      # DELETE /api/v1/game_keys/:id
      # Revoke (delete) a key. Authorized for the original donor, an admin, or
      # the service token (see require_donor_or_admin!).
      def destroy
        game_key.destroy!
        render json: { deleted: true }
      end

      # POST /api/v1/game_keys/:id/claim
      # Atomically claim an unclaimed key and reveal its `key_value` to the
      # claimer. A Discord caller claims as themselves; the service token claims
      # on behalf of the `claimed_by_user_id` it supplies.
      def claim
        claimant_id = resolve_claimant_id
        return render json: { error: "claimant_required" }, status: :unprocessable_entity if claimant_id.blank?

        claimed = RpgClubGameKey
          .where(key_id: params[:id], claimed_by_user_id: nil)
          .update_all(claimed_by_user_id: claimant_id, claimed_at: Time.current, updated_at: Time.current)

        if claimed.zero?
          # Nothing flipped: a missing key raises 404 here, while an existing
          # one was already claimed by someone else.
          RpgClubGameKey.find(params[:id])
          return render json: { error: "already_claimed" }, status: :conflict
        end

        record = RpgClubGameKey.includes(game: :images).find(params[:id])
        render json: { data: GameKeyResource.new(record, params: { reveal_key: true }).serializable_hash }
      end

      private

      # The key targeted by the member routes (show/destroy), with its linked
      # game and images preloaded for the embedded card. Memoized so the
      # authorization before_action and the action share a single lookup. A
      # missing key raises RecordNotFound (404) before any authz check runs.
      def game_key
        @game_key ||= RpgClubGameKey.includes(game: :images).find(params[:id])
      end

      # show/destroy operate on a specific key and (for show) reveal its secret,
      # so they're limited to the service token, the key's donor, or an admin —
      # the same audience the issue specifies for revocation. Reads stay open on
      # the listing endpoints, which never expose the secret.
      def require_donor_or_admin!
        return true if current_principal&.service?

        if current_principal&.discord_user?
          return true if current_principal.id.to_s == game_key.donor_user_id.to_s
          return true if current_principal.dev?
          return true if RpgClubUser.where(user_id: current_principal.id, role_admin: true).exists?
        end

        render json: { error: "forbidden" }, status: :forbidden
        false
      end

      # Donations set only the offer fields; the claim columns, identity and
      # timestamps are not client-writable (so a key can't be donated
      # pre-claimed or with a spoofed id/timestamp). When the donor links a game
      # but omits the title, fall back to the game's title so `game_title`
      # (the listing's sort key and the unlinked-display label) is always set.
      def donate_data
        attrs = request_data.except("key_id", "claimed_by_user_id", "claimed_at", "created_at", "updated_at")

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

      # require_owner! for #create resolves the owner from the donor named in
      # the request body.
      def resolve_owner_id
        params.dig(:data, :donor_user_id).presence
      end
    end
  end
end
