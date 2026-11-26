# frozen_string_literal: true

module Api
  module V1
    # A member's Patch Mark (spec api#510, ticket api#512): the number of the
    # newest Patch they have seen. The website reads it to mark unseen
    # Patches "NEW" and moves it forward when the member opens /patch-notes
    # or a Patch page. The session's `patch_notes_unseen` carries the same
    # answer for the sidebar.
    #
    # Only the member themself may read or set it. The Patch Mark only shapes
    # the website, so the bot's service token is refused too.
    class PatchMarksController < ApplicationController
      feature :patch_notes

      before_action :refuse_service!
      before_action :require_owner!

      # GET /api/v1/users/:user_id/patch_mark
      def show
        render json: { data: document(PatchMark.for(params[:user_id])) }
      end

      # PUT /api/v1/users/:user_id/patch_mark
      # Body: { "data": { "patch_mark": <Patch number> } }
      # Moves the Patch Mark forward. A number below the stored mark keeps
      # the stored one; a number past the newest published Patch is clamped
      # to it. Returns the stored mark.
      def update
        number = request_data["patch_mark"]
        unless number.is_a?(Integer) && number.positive?
          return render(json: { error: "patch_mark must be a positive whole number" }, status: :unprocessable_content)
        end

        render json: { data: document(PatchMark.advance!(params[:user_id], number)) }
      end

      private

      # require_owner! lets the service token act as any member; the Patch
      # Mark is the member's own, so it is refused here first.
      def refuse_service!
        gate_or_forbid(!current_principal.service?)
      end

      def document(mark)
        { user_id: params[:user_id], patch_mark: mark, unseen: PatchMark.unseen?(mark) }
      end
    end
  end
end
