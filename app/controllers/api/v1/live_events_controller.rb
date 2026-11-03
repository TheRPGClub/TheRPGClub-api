# frozen_string_literal: true

module Api
  module V1
    # Live events (web parity 2, #336). Moderators and up create, list and
    # read them; creating queues the `live_event_create` bot job, which makes
    # the forum thread and the Discord scheduled event and records each id
    # through the service-only update. The service token passes every gate.
    class LiveEventsController < ApplicationController
      before_action :require_moderator_or_above!, only: %i[index show create]
      before_action :require_service!, only: %i[update]

      # GET /api/v1/live_events, newest first.
      def index
        render_collection(LiveEvent.all, resource: LiveEventResource, default_order: { created_at: :desc, id: :desc })
      end

      # GET /api/v1/live_events/:id
      def show
        render_event(LiveEvent.find(params[:id]))
      end

      # POST /api/v1/live_events. JSON with an optional `image_url`, or
      # multipart with an optional `data[image]` file, stored in Backblaze.
      def create
        attrs = create_params
        upload = attrs.delete(:image)
        if upload.present? && attrs[:image_url].present?
          return render json: { error: "Send an image URL or an image file, not both" }, status: :unprocessable_entity
        end

        requester = current_principal.discord_user? ? current_principal.id.to_s : nil
        event = LiveEvent.new(attrs.merge(created_by_user_id: requester))
        event.validate!
        event.image_url = LiveEvents::ImageStorage.new.upload!(upload) if upload.present?

        LiveEvent.transaction do
          event.save!
          event.enqueue_creation!(requested_by: requester)
        end
        render_event(event, status: :created)
      rescue LiveEvents::ImageStorage::InvalidImageError => error
        render json: { error: error.message }, status: :unprocessable_entity
      rescue Backblaze::Client::ConfigurationError => error
        render json: { error: "backblaze_not_configured", message: error.message }, status: :unprocessable_entity
      rescue Backblaze::Client::RequestError => error
        render json: { error: "backblaze_request_failed", message: error.message }, status: :bad_gateway
      end

      # PATCH /api/v1/live_events/:id (service): the bot records the thread
      # id, the event id and the status as each step is done.
      def update
        event = LiveEvent.find(params[:id])
        event.update!(params.require(:data).permit(:discord_thread_id, :discord_event_id, :status))
        render_event(event)
      end

      private

      def create_params
        params.require(:data).permit(:topic, :starts_at, :ends_at, :image_url, :image).to_h.symbolize_keys
      end

      def render_event(event, status: :ok)
        render json: { data: LiveEventResource.new(event).serializable_hash }, status: status
      end
    end
  end
end
