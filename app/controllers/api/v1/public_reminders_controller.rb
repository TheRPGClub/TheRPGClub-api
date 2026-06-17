# frozen_string_literal: true

module Api
  module V1
    class PublicRemindersController < ApplicationController
      before_action :require_service!, only: %i[due]

      def index
        scope = RpgClubPublicReminder.all
        scope = scope.where(enabled: ActiveModel::Type::Boolean.new.cast(params[:enabled])) if params[:enabled].present?
        render_collection(scope, resource: PublicReminderResource, default_order: { due_at: :asc })
      end

      # GET /api/v1/public_reminders/due
      #
      # Service-only poll endpoint: returns enabled reminders whose `due_at` has
      # passed (`<= now`), oldest first. Backs the bot's PublicReminderService
      # poll so it no longer over-fetches every enabled reminder and filters by
      # due time client-side. Unpaginated — the bot needs every due reminder to
      # fire in a single cycle.
      def due
        scope = RpgClubPublicReminder
          .where(enabled: true)
          .where("due_at <= ?", Time.current)
          .order(due_at: :asc)
        render json: { data: PublicReminderResource.new(scope).serializable_hash }
      end

      def show
        render json: { data: RpgClubPublicReminder.find(params[:id]).as_json }
      end

      def create
        record = RpgClubPublicReminder.create!(request_data)
        render json: { data: record.as_json }, status: :created
      end

      def update
        record = RpgClubPublicReminder.find(params[:id])
        record.update!(request_data)
        render json: { data: record.as_json }
      end

      def destroy
        RpgClubPublicReminder.find(params[:id]).destroy!
        render json: { deleted: true }
      end
    end
  end
end
