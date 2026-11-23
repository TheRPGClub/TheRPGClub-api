# frozen_string_literal: true

module Api
  module V1
    # A member's Dashboard Panels (spec api#421, ticket api#422; docs/adr/0012):
    # the panels of club or personal activity they show below the current
    # issue on their own dashboard, in their order.
    #
    # Only the member themself may read or change it. Panels only shape the
    # website, so the bot's service token is refused too, as for Pinned Pages.
    class DashboardPanelsController < ApplicationController
      before_action :refuse_service!
      before_action :require_owner!

      # GET /api/v1/users/:user_id/dashboard_panels
      def show
        render json: { data: document }
      end

      # PUT /api/v1/users/:user_id/dashboard_panels
      # Body: { "data": { "panels": ["<panel key>", ...] } }
      # Replaces the member's whole list with `panels`, in order: show, hide
      # and reorder all send the full list the member sees. Panels they can't
      # see right now are kept (DashboardPanels::List). An unknown key or a
      # duplicate refuses the whole change with 422.
      def update
        error = list.save(request_data["panels"])
        return render(json: { error: error }, status: :unprocessable_content) if error

        render json: { data: document }
      end

      # DELETE /api/v1/users/:user_id/dashboard_panels
      # Resets the member to the club default. Returns the document.
      def destroy
        list.reset!
        render json: { data: document }
      end

      # POST /api/v1/users/:user_id/dashboard_panels/seen
      # Optional body: { "data": { "panels": ["<panel key>", ...] } }
      # The member opened edit mode: the panels listed (every panel without a
      # body) are no longer new to them. Returns the document.
      def seen
        error = list.seen!(params.key?(:data) ? request_data["panels"] : nil)
        return render(json: { error: error }, status: :unprocessable_content) if error

        render json: { data: document }
      end

      private

      def refuse_service!
        gate_or_forbid(!current_principal.service?)
      end

      def list
        @list ||= begin
          user = RpgClubUser.find_by(user_id: params[:user_id])
          access = Features::Access.for_viewer(user, staff: admin_or_above?)
          DashboardPanels::List.new(params[:user_id], DashboardPanels::Viewer.new(access), user)
        end
      end

      def document
        { user_id: params[:user_id], panels: list.visible, catalogue: list.catalogue, customised: list.customised? }
      end
    end
  end
end
