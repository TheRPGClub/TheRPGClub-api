# frozen_string_literal: true

module Api
  module V1
    # A member's Pinned Pages (spec api#416, tickets api#418, api#419; docs/adr/0012):
    # the pages they put at the top of their own sidebar, in their order.
    #
    # Only the member themself may read or change it. Pins only shape the
    # website, so the bot's service token is refused too, as for Feature
    # Preferences.
    class PinnedPagesController < ApplicationController
      include PinnedPagesViewer

      before_action :refuse_service!
      before_action :require_owner!

      # GET /api/v1/users/:user_id/pinned_pages
      def show
        render json: { data: document }
      end

      # PUT /api/v1/users/:user_id/pinned_pages
      # Body: { "data": { "pages": ["<page key>", ...] } }
      # Replaces the member's whole list with `pages`, in order: pin, unpin and
      # reorder all send the full list the member sees. Pins they can't see
      # right now are kept (PinnedPages::List). An unknown key, a duplicate or
      # more than PinnedPages::LIMIT pins refuses the whole change with 422.
      def update
        pages = request_data["pages"]
        error = list.error_for(pages)
        return render(json: { error: error }, status: :unprocessable_content) if error

        list.replace!(pages)
        render json: { data: document }
      end

      # DELETE /api/v1/users/:user_id/pinned_pages (ticket api#419)
      # Resets the member to the club default: their saved list is dropped, so
      # later changes to the default reach them again. Returns the document.
      def destroy
        list.reset!
        render json: { data: document }
      end

      private

      def refuse_service!
        gate_or_forbid(!current_principal.service?)
      end

      def list
        @list ||= PinnedPages::List.new(params[:user_id], pinned_viewer(RpgClubUser.find_by(user_id: params[:user_id])))
      end

      def document
        { user_id: params[:user_id], pages: list.visible, customised: list.customised? }
      end
    end
  end
end
