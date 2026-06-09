# frozen_string_literal: true

module Api
  module V1
    # Per-user personal reminders (bot parity, #41). These are the DM reminders
    # the bot delivers to a single user, distinct from the channel-wide
    # PublicReminders. The delivery columns (`sent_at`, `failure_count`,
    # `failed_at`) are bot-managed and read-only here — see #writable_data.
    class RemindersController < ApplicationController
      before_action :require_owner!, only: %i[create update destroy]

      # GET /api/v1/users/:user_id/reminders
      def index
        scope = UserReminder.where(user_id: params[:user_id])
        render_collection(scope, resource: ReminderResource, default_order: { remind_at: :asc, reminder_id: :asc })
      end

      # GET /api/v1/reminders/:id
      def show
        record = UserReminder.find(params[:id])
        render json: { data: ReminderResource.new(record).serializable_hash }
      end

      # POST /api/v1/users/:user_id/reminders
      def create
        record = UserReminder.create!(writable_data.merge("user_id" => params[:user_id]))
        record.reload
        render json: { data: ReminderResource.new(record).serializable_hash }, status: :created
      end

      # PATCH/PUT /api/v1/reminders/:id
      #
      # Also covers snooze: a client reschedules by pushing `remind_at` forward
      # (and may flip `is_noisy`).
      def update
        record = UserReminder.find(params[:id])
        record.update!(writable_data)
        record.reload
        render json: { data: ReminderResource.new(record).serializable_hash }
      end

      # DELETE /api/v1/reminders/:id
      def destroy
        UserReminder.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      # The bot's send loop owns the delivery columns, so strip them from any
      # API write — they are read-only to consumers (#41).
      def writable_data
        request_data.except("sent_at", "failure_count", "failed_at")
      end

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        UserReminder.find_by(reminder_id: params[:id])&.user_id
      end
    end
  end
end
