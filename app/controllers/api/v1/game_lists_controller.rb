# frozen_string_literal: true

module Api
  module V1
    # Game Lists (GLOSSARY.md, "Game List"; spec api#442, ticket api#446).
    # Members keep named lists of GameDB games; the club owns lists too. Who
    # may read and change one is GameLists::Actor's decision: a Private list
    # is its owner's alone, staff included. Gated by the `game_lists` Feature,
    # as are a member's lists (GET /users/:user_id/game_lists) and a game's
    # (GET /games/:id/game_lists).
    #
    # The bot acts for a Discord user with the service token and names them
    # (GameListActing). Refusals carry `{ error, message }`; `message` is
    # written for members.
    class GameListsController < ApplicationController
      include GameListActing

      feature :game_lists

      # The fields of `data` a list takes on create; `club` is create-only.
      FIELDS = %w[name description visibility sort].freeze

      WRITES = %i[create update destroy add_entry update_entry remove_entry order].freeze

      before_action :require_acting_member!, only: WRITES

      rescue_from ActiveRecord::RecordInvalid do |error|
        render json: { error: "invalid_game_list", message: error.record.errors.full_messages.to_sentence },
          status: :unprocessable_content
      end
      rescue_from GameLists::Refused do |error|
        render json: { error: error.code, message: error.message, **error.details }, status: error.status
      end

      # GET /api/v1/game_lists?q=souls&game_id=12&owner=club
      #
      # The lists the actor may read: club lists first, then the most
      # recently changed. `q` keeps those whose name contains it, ignoring
      # case; `game_id` those holding that game; `owner` the club's (`club`)
      # or one member's (their user id).
      def index
        scope = actor.readable(GameList.all)
        scope = name_filter(scope)
        scope = scope.where(id: GameListEntry.where(game_id: params[:game_id]).select(:game_list_id)) if params[:game_id].present?
        scope = owner_filter(scope)
        render_lists(scope)
      end

      # GET /api/v1/users/:user_id/game_lists
      #
      # A member's lists the actor may read: all of their own, another
      # member's Members-visible ones. Most recently changed first.
      def user_index
        render_lists(actor.readable(GameList.where(owner_user_id: params[:user_id].to_s)))
      end

      # GET /api/v1/games/:id/game_lists
      #
      # The lists holding the game that the actor may read, club lists
      # first; `meta.count` is how many there are.
      def game_index
        game = GamedbGame.find(params[:id])
        render_lists(actor.readable(GameList.where(id: GameListEntry.where(game_id: game.game_id).select(:game_list_id))))
      end

      # GET /api/v1/game_lists/:id
      def show
        render_list(find_readable)
      end

      # POST /api/v1/game_lists
      # Body: { "data": { name, description, visibility, sort, club } }
      #
      # The acting member owns it, or the club with `club` (Moderator and
      # above).
      def create
        data = request_data
        club = ActiveModel::Type::Boolean.new.cast(data["club"]) ? true : false
        return forbid(GameLists::Refusals::CLUB) if club && !actor.can_create_club?

        attributes = list_fields(data)
        return if performed?

        list = GameList.create!(attributes.merge(owner_user_id: club ? nil : actor.user_id))
        render_list(list, status: :created)
      end

      # PATCH /api/v1/game_lists/:id
      # Body: { "data": { any of name, description, visibility, sort; confirm } }
      #
      # Making a list that feeds a Challenge Private needs `confirm`
      # (GameLists::Lifecycle).
      def update
        list = find_readable
        return forbid(GameLists::Refusals::EDIT) unless actor.can_edit?(list)

        data = request_data
        attributes = list_fields(data)
        return if performed?
        if attributes.key?("visibility") && attributes["visibility"] != list.visibility &&
           !actor.can_change_visibility?(list)
          return forbid(GameLists::Refusals::VISIBILITY)
        end

        render_list(GameLists::Lifecycle.update!(list, attributes, confirm: confirmed?(data["confirm"])))
      end

      # DELETE /api/v1/game_lists/:id?confirm=true
      #
      # Deleting a list that feeds a Challenge needs `confirm`; a member's
      # such list goes to the club instead (`taken_over: true`).
      def destroy
        list = find_readable
        return forbid(GameLists::Refusals::DELETE) unless actor.can_delete?(list)

        taken_over = GameLists::Lifecycle.destroy!(list, confirm: confirmed?(params[:confirm]))
        render json: { data: { id: list.id, deleted: true, taken_over: taken_over } }
      end

      # POST /api/v1/game_lists/:id/entries/:game_id
      # Body: { "data": { "note": "..." } } (optional)
      #
      # Adds the game last in the ranked order.
      def add_entry
        list = find_editable
        return if performed?

        note = note_param(optional: true)
        return if performed?

        entry = GameLists::Entries.add!(list, params[:game_id], note: note)
        render_entry(entry, status: :created)
      end

      # PATCH /api/v1/game_lists/:id/entries/:game_id
      # Body: { "data": { "note": "..." | null } }
      def update_entry
        list = find_editable
        return if performed?

        note = note_param(optional: false)
        return if performed?

        render_entry(GameLists::Entries.note!(list, params[:game_id], note))
      end

      # DELETE /api/v1/game_lists/:id/entries/:game_id
      def remove_entry
        list = find_editable
        return if performed?

        entry = GameLists::Entries.remove!(list, params[:game_id])
        render json: { data: { game_list_id: list.id, game_id: entry.game_id, deleted: true } }
      end

      # PUT /api/v1/game_lists/:id/entries/order
      # Body: { "data": { "game_ids": [...] } }
      #
      # Sets the ranked order; returns the list.
      def order
        list = find_editable
        return if performed?

        GameLists::Entries.reorder!(list, request_data["game_ids"])
        render_list(list)
      end

      private

      # A list the actor may read; any other is not found, so a Private
      # list's existence stays private.
      def find_readable
        actor.readable(GameList.all).find(params[:id])
      end

      def find_editable
        list = find_readable
        forbid(GameLists::Refusals::EDIT) unless actor.can_edit?(list)
        list
      end

      def render_lists(scope)
        render_collection(GameListResource.preloaded(scope), resource: GameListResource,
          default_order: GameList::INDEX_ORDER,
          params: { actor: actor }, prepare: ->(lists) { GameLists::Overview.of(lists) })
      end

      def render_list(list, status: :ok)
        list = GameListResource.preloaded(GameList.where(id: list.id)).first!
        render json: { data: GameListResource.new(list, params: { actor: actor, detail: true }).serializable_hash },
          status: status
      end

      def render_entry(entry, status: :ok)
        entry = GameListEntry.where(game_list_id: entry.game_list_id, game_id: entry.game_id).preload(game: :images).first!
        render json: { data: GameListEntryResource.new(entry).serializable_hash }, status: status
      end

      # The list fields `data` gives, each text or null; 422 otherwise.
      def list_fields(data)
        FIELDS.each_with_object({}) do |field, attributes|
          next unless data.key?(field)

          value = data[field]
          return refuse("#{field} must be text") unless value.nil? || value.is_a?(String)

          attributes[field] = value
        end
      end

      # `data.note`: text or null. Required on a note edit.
      def note_param(optional:)
        data = params[:data].respond_to?(:key?) ? params[:data] : {}
        return refuse("note is required") if !optional && !data.key?(:note)

        note = data[:note]
        return refuse("note must be text") unless note.nil? || note.is_a?(String)

        note
      end

      def name_filter(scope)
        query = params[:q].to_s.strip
        return scope if query.empty?

        scope.where("game_lists.name ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(query)}%")
      end

      def owner_filter(scope)
        case params[:owner].presence
        when nil then scope
        when "club" then scope.where(owner_user_id: nil)
        else scope.where(owner_user_id: params[:owner].to_s)
        end
      end

      def confirmed?(value) = ActiveModel::Type::Boolean.new.cast(value) ? true : false

      def refuse(message)
        render json: { error: "invalid_game_list", message: message }, status: :unprocessable_content
        nil
      end
    end
  end
end
