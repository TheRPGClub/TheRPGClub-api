# frozen_string_literal: true

module Api
  module V1
    # Now-playing lists + mutations (bot parity, #104). The Discord bot's
    # `/now-playing` command migrates off direct SQL onto these endpoints. Reads
    # are loaded through `UserNowPlaying.with_now_playing_details` so the journal
    # aggregates and derived `linked_thread_id` are populated.
    #
    # Auth: every list is open to any authenticated caller (the cross-member
    # `index` also feeds the dashboard's Club Now Playing panel, api#423);
    # create/update/destroy are owner-only (the bot's service token counts as
    # the owner).
    class NowPlayingController < ApplicationController
      include CodedRefusals
      include ShelfPositioning
      include ShelfPlaytime

      feature :now_playing

      before_action :require_owner!, only: %i[create update destroy]

      # GET /api/v1/now_playing
      #
      # Every active member's now-playing entries (bots and members who have left
      # are excluded), each with its embedded user/game/platform. The optional
      # `game_ids[]` filter narrows to entries of any of the given games (the
      # bot's ThreadLinkPromptService check); `q` keeps entries whose game title
      # matches (case-insensitive substring) for the `/now-playing search`
      # autocomplete. Both serve from the same rich shape. Newest first, `per`
      # honoured: the website's Club Now Playing panel asks for the latest few.
      def index
        scope = UserNowPlaying.with_now_playing_details
          .joins(:user)
          .where(rpg_club_users: { is_bot: false, server_left_at: nil })
          .preload(:user, :platform, game: :images)

        game_ids = Array(params[:game_ids]).map(&:to_i).reject(&:zero?)
        scope = scope.where(gamedb_game_id: game_ids) if game_ids.any?

        if params[:q].present?
          titles = GamedbGame.where("title ILIKE ?", "%#{sanitize_like(params[:q])}%").select(:game_id)
          scope = scope.where(gamedb_game_id: titles)
        end

        render_collection(scope, resource: NowPlayingMemberEntryResource,
          default_order: { added_at: :desc, entry_id: :desc })
      end

      # GET /api/v1/games/:id/now_playing
      def game_index
        scope = UserNowPlaying.with_now_playing_details.where(gamedb_game_id: params[:id]).preload(:user)
        render_collection(scope, resource: NowPlayingUserEntryResource,
          default_order: { added_at: :desc, entry_id: :desc })
      end

      # GET /api/v1/users/:user_id/now_playing
      #
      # The user's own list, ordered the way the bot displays it: ascending
      # `sort_order` (nulls last), then newest first.
      def user_index
        scope = UserNowPlaying.with_now_playing_details.where(user_id: params[:user_id]).preload(:platform, game: :images)
        render_shelf(scope, resource: NowPlayingEntryResource, default_order: UserNowPlaying::SHELF_ORDER)
      end

      # GET /api/v1/now_playing/:id
      def show
        render json: { data: serialize_entry(params[:id], NowPlayingMemberEntryResource) }
      end

      # POST /api/v1/users/:user_id/now_playing
      #
      # Adds an entry to the user's list. `sort_order` is assigned server-side
      # (appended last) and the per-user max of 10 is enforced.
      #
      # Starting a game moves it off the backlog (web-parity #286, formerly the
      # bot's `Member.addNowPlaying` orchestration): in one transaction, every
      # backlog row the user has for the game is removed, and when no `note` is
      # supplied the backlog note carries over. If the entry can't be created the
      # backlog is left as it was. A game already on the list is 409
      # `already_playing` (the backlog is untouched).
      #
      # It also opens a Playthrough of the game when none is open (spec
      # api#457). Taking the game off the list leaves the Playthrough open.
      def create
        data = create_data.merge("user_id" => params[:user_id])
        if data["gamedb_game_id"].present? &&
           UserNowPlaying.exists?(user_id: params[:user_id], gamedb_game_id: data["gamedb_game_id"])
          return render json: { error: "already_playing", message: "This game is already on the now-playing list." },
            status: :conflict
        end

        record = ActiveRecord::Base.transaction do
          backlog = UserGameBacklog.where(user_id: params[:user_id], gamedb_game_id: data["gamedb_game_id"])
            .order(sort_order: :asc, created_at: :desc).to_a
          data["note"] = backlog.map(&:note).find(&:present?) if data["note"].blank? && backlog.any?
          backlog.each(&:destroy!)
          UserNowPlaying.create!(data).tap do |entry|
            next unless entry.gamedb_game_id

            Playtime::Playthroughs.start_unless_open(user_id: entry.user_id, game_id: entry.gamedb_game_id)
          end
        end
        render json: { data: serialize_entry(record.entry_id, NowPlayingEntryResource) }, status: :created
      end

      # PATCH/PUT /api/v1/now_playing/:id
      #
      # Partial update of `note`, `platform_id`, `sort_order` and/or `added_at`
      # (the day the member started playing; 422 `added_in_future` after today).
      # A `position` (1-based) moves the entry within the member's list and
      # renumbers the rest (ShelfOrder); 422 `invalid_position` when bad.
      def update
        record = UserNowPlaying.find(params[:id])
        position = shelf_position
        return if performed?

        record.update_at_position!(update_data, position)
        render json: { data: serialize_entry(record.entry_id, NowPlayingMemberEntryResource) }
      rescue ActiveRecord::RecordInvalid => e
        render_coded_refusal(e, %i[added_in_future])
      end

      # DELETE /api/v1/now_playing/:id
      def destroy
        UserNowPlaying.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      # Re-fetch through the details scope so the serialized entry carries the
      # journal aggregates and derived linked-thread id.
      def serialize_entry(entry_id, resource)
        record = UserNowPlaying.with_now_playing_details.preload(:user, :game, :platform).find(entry_id)
        resource.new(record).serializable_hash
      end

      # The columns a client may set on create (`user_id` comes from the path,
      # `sort_order`/`note_updated_at` are server-managed).
      def create_data
        request_data.slice("gamedb_game_id", "platform_id", "note")
      end

      # The columns a client may change on update (the issue's `note`,
      # `platform_id`, `sort_order`, plus `added_at`, the member's started day;
      # `note_updated_at` is stamped server-side).
      def update_data
        request_data.slice("note", "platform_id", "sort_order", "added_at")
      end

      def sanitize_like(value)
        ActiveRecord::Base.sanitize_sql_like(value.to_s.strip)
      end

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        UserNowPlaying.find_by(entry_id: params[:id])&.user_id
      end
    end
  end
end
