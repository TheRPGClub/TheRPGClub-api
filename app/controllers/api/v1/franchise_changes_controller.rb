# frozen_string_literal: true

module Api
  module V1
    # A Franchise's change history and undo (spec api#442, ticket api#444).
    # Gamedb::FranchiseEditor records every change; Regulars and above read
    # the history and undo link, unlink, Mainline and rename changes. Rights:
    # FranchiseRights.
    class FranchiseChangesController < ApplicationController
      include FranchiseRights
      include TaxonomyEndpoints

      # GET /api/v1/franchises/:id/changes
      #
      # Newest first, paged (`page`, `per`). A merged Franchise still has its
      # history; a deleted one 404s.
      def index
        return unless require_editor!

        franchise = GamedbFranchise.find(params[:id])
        scope = GamedbFranchiseChange.where(franchise_id: franchise.franchise_id)
        render_collection(scope, resource: FranchiseChangeResource, default_order: { id: :desc }, default_per: 25,
          prepare: ->(changes) { row_params(changes, franchise) })
      end

      # POST /api/v1/franchise_changes/:id/undo
      #
      # Undoes the change and answers with it, now undone. 422
      # `not_undoable` for create, merge and delete; 409 `already_undone`,
      # or `superseded` when a later change, a merge or a change outside the
      # history touched the same game or name.
      def undo
        return unless require_editor!

        change = GamedbFranchiseChange.find(params[:id])
        Gamedb::FranchiseEditor.new(user_id: acting_user_id).undo!(change)
        # A rename's undo changes the name the Franchise list shows.
        bump_taxonomy_version(GamedbFranchise) if change.action == "rename"
        render json: { data: FranchiseChangeResource.new(change, params: row_params([ change ], nil)).serializable_hash }
      rescue Gamedb::FranchiseEditor::UndoRefused => e
        render json: { error: e.reason.to_s, message: UNDO_REFUSALS.fetch(e.reason) },
          status: e.reason == :not_undoable ? :unprocessable_content : :conflict
      end

      UNDO_REFUSALS = {
        not_undoable: "Creating, merging and deleting a Franchise can't be undone.",
        already_undone: "That change was already undone.",
        superseded: "A later change touched the same game or name, so this one can't be undone."
      }.freeze

      private

      def row_params(changes, franchise)
        user_ids = changes.flat_map { |change| [ change.user_id, change.undone_by ] }.compact.uniq
        names = RpgClubUser.where(user_id: user_ids).pluck(:user_id, :username).to_h
        titles = GamedbGame.where(game_id: changes.filter_map(&:game_id)).pluck(:game_id, :title).to_h
        can_undo = franchise.nil? || !franchise.merged?
        undoable = changes.select { |change| can_undo && change.undoable_action? && !change.superseded? }.to_set(&:id)

        { titles: titles, names: names, can_edit: can_edit?, undoable: undoable }
      end
    end
  end
end
