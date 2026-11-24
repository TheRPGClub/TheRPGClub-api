# frozen_string_literal: true

module Api
  module V1
    # Franchises (GLOSSARY.md). The list and search are the shared taxonomy
    # endpoints (TaxonomyEndpoints). A Franchise's page groups its games as
    # Mainline, Other and Add-ons, with what the viewer may change
    # (Gamedb::FranchiseGames). Regulars and above link and unlink games, set
    # Mainline and create Franchises with no IGDB id (spec api#442), all
    # through Gamedb::FranchiseEditor. The bot keeps its admin/service
    # upsert by IGDB id on `POST /franchises`.
    #
    # Rights come from the acting member's stored roles (docs/adr/0005): the
    # signed-in member, or the member the bot names in `acting_user_id`.
    class FranchisesController < ApplicationController
      include TaxonomyEndpoints
      include ActingMember

      EDIT_REFUSAL = "You need the Regulars role to change Franchises."

      serves_taxonomy GamedbFranchise, resource: FranchiseResource

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
      # (TaxonomyEndpoints#upsert_taxonomy).
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
        return unless require_editor!

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
        return unless require_editor!

        editor.unlink!(franchise, game)
        head :no_content
      end

      private

      def upsert_by_igdb_id
        return unless require_admin_or_service!

        upsert_taxonomy(GamedbFranchise, FranchiseResource, :igdb_franchise_id)
      end

      # A DELETE carries no body, so the bot names its member in the query.
      def acting_user_id
        return @acting_user_id if defined?(@acting_user_id)
        return super unless current_principal&.service? && request.delete?

        @acting_user_id = params[:acting_user_id].presence&.to_s
      end

      def franchise = @franchise ||= GamedbFranchise.find(params[:id])

      def game = @game ||= GamedbGame.select(:game_id, :updated_at).find(params[:game_id])

      def editor = Gamedb::FranchiseEditor.new(user_id: acting_user_id)

      def can_edit?
        member_rights { |member| member.role_regular? || member.moderator_or_above? } ||
          (!current_principal.service? && regular_or_staff?)
      end

      def can_admin?
        member_rights(&:admin_or_above?) || (!current_principal.service? && admin_or_above?)
      end

      # For the bot, the named member's stored roles (false when it names
      # none); nil for a signed-in member, whose roles StaffGates reads.
      def member_rights
        return nil unless current_principal.service?

        acting_member ? (yield(acting_member) ? true : false) : false
      end

      # 400 for the bot without an acting member; 403 unless Regular or
      # above.
      def require_editor!
        if current_principal.service? && acting_user_id.blank?
          render json: { error: "acting_user_id required" }, status: :bad_request
          return false
        end
        return true if can_edit?

        render json: { error: "forbidden", message: EDIT_REFUSAL }, status: :forbidden
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
