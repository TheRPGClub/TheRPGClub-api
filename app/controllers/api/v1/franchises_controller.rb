# frozen_string_literal: true

module Api
  module V1
    # Franchises (GLOSSARY.md). The list and search are the shared taxonomy
    # endpoints (TaxonomyEndpoints). A Franchise's page groups its games as
    # Mainline, Other and Add-ons, with what the viewer may change
    # (Gamedb::FranchiseGames). Regulars and above link and unlink games, set
    # Mainline, set a game's Add-on parent and create Franchises with no IGDB
    # id; Admins and above
    # rename, merge and delete them (spec api#442), all through
    # Gamedb::FranchiseEditor, which records each change in the history
    # (FranchiseChangesController). The bot keeps its admin/service upsert
    # by IGDB id on `POST /franchises`.
    #
    # Rights: FranchiseRights. A merged Franchise leaves the list and
    # search, still shows (with `merged_into_id`), and refuses changes.
    class FranchisesController < ApplicationController
      include TaxonomyEndpoints
      include FranchiseRights

      serves_taxonomy GamedbFranchise, resource: FranchiseResource, scope: -> { GamedbFranchise.current }

      # GET /api/v1/franchises/:id
      #
      # The Franchise's columns, its games grouped (`games`: `mainline`,
      # `other`, `add_ons`) and `viewer`: `{ can_edit, can_admin }`.
      def show
        franchise = GamedbFranchise.find(params[:id])

        render json: { data: FranchiseResource.new(franchise).serializable_hash.merge(
          "games" => Gamedb::FranchiseGames.of(franchise).as_json,
          "viewer" => { "can_edit" => can_edit?, "can_admin" => can_admin? }
        ) }
      end

      # POST /api/v1/franchises
      # Body: { "data": { "name" } }, or { "data": { "igdb_franchise_id", "name" } }
      #
      # Without an IGDB id, a Regular or above creates a new Franchise
      # (201). With one, it is the admin/service find-or-create by IGDB id
      # (upsert_by_igdb_id).
      def create
        return upsert_by_igdb_id if request_data.key?("igdb_franchise_id")
        return unless require_editor!

        franchise = editor.create!(name: request_data["name"])
        bump_taxonomy_version(GamedbFranchise)
        render json: { data: FranchiseResource.new(franchise).serializable_hash }, status: :created
      end

      # PUT /api/v1/franchises/:id/games/:game_id
      # Body: { "data": { "mainline": true|false, "parent_game_id": id|null } }
      # (data and both keys optional)
      #
      # Links the game (as `manual`) if it isn't linked, sets Mainline when
      # `mainline` is given, and when `parent_game_id` is given makes the
      # game an Add-on of that GameDB game (null: not an Add-on), locked
      # against IGDB re-imports. Answers with the link and the game's parent.
      # 422 for a parent refused (Gamedb::FranchiseEditor::PARENT_REFUSALS,
      # `parent_not_found`, `invalid_parent`); nothing changes then.
      def link_game
        return unless require_editor! && require_unmerged!

        mainline = link_mainline
        return if performed?

        parent = link_parent
        return if performed?

        link = editor.link!(franchise, game, mainline: mainline, parent: parent)
        render json: { data: link_json(link).merge(parent_json) }
      rescue Gamedb::FranchiseEditor::ParentRefused => e
        refuse_parent(e.reason)
      end

      # DELETE /api/v1/franchises/:id/games/:game_id
      #
      # Unlinks the game and remembers it, so an IGDB re-import doesn't add
      # it back. 204, also when it wasn't linked.
      def unlink_game
        return unless require_editor! && require_unmerged!

        editor.unlink!(franchise, game)
        head :no_content
      end

      # PATCH /api/v1/franchises/:id
      # Body: { "data": { "name" } }
      #
      # Admins and above. Renames the Franchise and locks the name, so IGDB
      # re-imports keep it.
      def update
        return unless require_franchise_admin! && require_unmerged!

        editor.rename!(franchise, name: request_data["name"])
        bump_taxonomy_version(GamedbFranchise)
        render json: { data: FranchiseResource.new(franchise).serializable_hash }
      end

      # POST /api/v1/franchises/:id/merge
      # Body: { "data": { "into_id" } }
      #
      # Admins and above. Merges this Franchise into `into_id` and answers
      # with the target.
      def merge
        return unless require_franchise_admin!

        target = GamedbFranchise.find(request_data["into_id"])
        editor.merge!(franchise, into: target)
        bump_taxonomy_version(GamedbFranchise)
        render json: { data: FranchiseResource.new(target.reload).serializable_hash }
      rescue Gamedb::FranchiseEditor::MergeRefused => e
        message = e.reason == :invalid_merge ? "A Franchise can't be merged into itself." : "That Franchise was merged into another."
        render json: { error: e.reason.to_s, message: message }, status: :unprocessable_content
      end

      # DELETE /api/v1/franchises/:id
      #
      # Admins and above. Deletes the Franchise and takes it out of every
      # Pool's sources; an IGDB Franchise isn't created again by re-imports.
      def destroy
        return unless require_franchise_admin!

        editor.delete!(franchise)
        bump_taxonomy_version(GamedbFranchise)
        head :no_content
      end

      private

      # The upsert goes through GamedbFranchise.for_igdb_ref, as an IGDB
      # import does: a merged Franchise answers with its target (200), and
      # one an Admin deleted is refused (422 `franchise_deleted`) rather
      # than made again.
      def upsert_by_igdb_id
        return unless require_admin_or_service!

        igdb_id = request_data["igdb_franchise_id"].presence
        if igdb_id.blank?
          return render(json: { error: "igdb_franchise_id is required" }, status: :unprocessable_content)
        end

        known = GamedbFranchise.exists?(igdb_franchise_id: igdb_id)
        franchise = GamedbFranchise.for_igdb_ref({ igdb_id: igdb_id, name: request_data["name"] })
        return refuse_deleted unless franchise

        bump_taxonomy_version(GamedbFranchise) unless known
        render json: { data: FranchiseResource.new(franchise).serializable_hash }, status: known ? :ok : :created
      end

      def refuse_deleted
        render json: { error: "franchise_deleted",
                       message: "An Admin deleted this Franchise, so it isn't made again." },
          status: :unprocessable_content
      end

      def franchise = @franchise ||= GamedbFranchise.find(params[:id])

      def game = @game ||= GamedbGame.select(:game_id, :updated_at).find(params[:game_id])

      def editor = Gamedb::FranchiseEditor.new(user_id: acting_user_id)

      # 422 `franchise_merged` for a change to a merged Franchise (the
      # target is the one to change).
      def require_unmerged!
        return true unless franchise.merged?

        render json: { error: "franchise_merged", message: "This Franchise was merged into another.",
                       merged_into_id: franchise.merged_into_id }, status: :unprocessable_content
        false
      end

      # `data.mainline` as true, false or nil (not given); 422 for anything
      # else.
      def link_mainline
        value = params[:data].respond_to?(:key?) ? params[:data][:mainline] : nil
        return value if [ true, false, nil ].include?(value)

        render json: { error: "invalid_mainline", message: "mainline must be true or false" },
          status: :unprocessable_content
      end

      # `data.parent_game_id`: :keep when not given, nil for null, else the
      # GamedbGame; 422 `invalid_parent` for a value that isn't an id and
      # `parent_not_found` for an unknown game.
      def link_parent
        data = params[:data]
        return :keep unless data.respond_to?(:key?) && data.key?(:parent_game_id)

        value = data[:parent_game_id]
        return nil if value.nil?

        id = value.is_a?(Integer) || value.to_s.match?(/\A\d+\z/) ? value.to_i : nil
        return refuse_parent(:invalid_parent) unless id

        GamedbGame.select(:game_id, :igdb_id, :title, :parent_igdb_id).find_by(game_id: id) ||
          refuse_parent(:parent_not_found)
      end

      PARENT_REFUSALS = {
        invalid_parent: "parent_game_id must be a game id or null.",
        parent_not_found: "That parent game isn't in GameDB.",
        parent_is_self: "A game can't be its own parent.",
        parent_not_igdb: "The parent game has no IGDB id, so it can't be a parent.",
        parent_is_add_on: "That game is an Add-on itself, so it can't be a parent.",
        game_has_add_ons: "This game has Add-ons of its own, so it can't become an Add-on."
      }.freeze

      def refuse_parent(reason)
        render json: { error: reason.to_s, message: PARENT_REFUSALS.fetch(reason) }, status: :unprocessable_content
        nil
      end

      # The game's parent after the change: `parent_game_id` is null when the
      # game isn't an Add-on or its parent isn't in GameDB.
      def parent_json
        igdb_id, name, locked = GamedbGame.where(game_id: game.game_id)
          .pick(:parent_igdb_id, :parent_game_name, :parent_locked)
        { parent_game_id: igdb_id && GamedbGame.where(igdb_id: igdb_id).pick(:game_id),
          parent_igdb_id: igdb_id, parent_game_name: name, parent_locked: locked }
      end

      def link_json(link)
        link.slice(:franchise_id, :game_id, :source, :mainline, :created_at, :created_by)
      end
    end
  end
end
