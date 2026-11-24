# frozen_string_literal: true

module Api
  module V1
    # Franchises (GLOSSARY.md). The list and search are the shared taxonomy
    # endpoints (TaxonomyEndpoints). A Franchise's page groups its games as
    # Mainline, Other and Add-ons, with what the viewer may change
    # (Gamedb::FranchiseGames). Regulars and above link and unlink games, set
    # Mainline and create Franchises with no IGDB id; Admins and above
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
      # Body: { "data": { "mainline": true|false } } (data optional)
      #
      # Links the game (as `manual`) if it isn't linked, and sets Mainline
      # when `mainline` is given. Answers with the link.
      def link_game
        return unless require_editor! && require_unmerged!

        mainline = link_mainline
        return if performed?

        link = editor.link!(franchise, game, mainline: mainline)
        render json: { data: link_json(link) }
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

      def link_json(link)
        link.slice(:franchise_id, :game_id, :source, :mainline, :created_at, :created_by)
      end
    end
  end
end
