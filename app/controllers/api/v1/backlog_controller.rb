# frozen_string_literal: true

module Api
  module V1
    class BacklogController < ApplicationController
      before_action :require_owner!, only: %i[pick create update destroy]

      # Caller-settable columns. `user_id` comes from the path (or the existing
      # record) and the key is generated, so neither is accepted in the body.
      WRITABLE_ATTRS = %w[gamedb_game_id platform_id note sort_order].freeze

      def index
        scope = UserGameBacklog.where(user_id: params[:user_id]).preload(:game, :platform)
        render_collection(scope, resource: BacklogEntryResource, default_order: { sort_order: :asc, created_at: :desc })
      end

      # GET /api/v1/users/:user_id/backlog/pick
      #
      # Suggests a game to play next (the bot's `/backlog pick`); see
      # BacklogPicker. Owner-only, like the bot's self-only command. Without a
      # `seed` the server draws one and returns it in `meta.seed`, so the client
      # rerolls by repeating the request with `position = meta.next_position`.
      # `data` is null when nothing qualifies.
      def pick
        options = pick_options
        return if performed?

        result = BacklogPicker.new(user_id: params[:user_id], **options).call
        render json: {
          data: result.pick && BacklogPickResource.new(result.pick).serializable_hash,
          meta: {
            seed: options[:seed], position: result.position, next_position: result.next_position,
            wrapped: result.wrapped, total: result.total, platforms: result.platforms
          }
        }
      end

      def show
        record = UserGameBacklog.includes(:game, :platform).find(params[:id])
        render json: { data: BacklogEntryResource.new(record).serializable_hash }
      end

      def create
        record = UserGameBacklog.create!(writable_data.merge("user_id" => params[:user_id]))
        record.reload
        render json: { data: BacklogEntryResource.new(record).serializable_hash }, status: :created
      end

      def update
        record = UserGameBacklog.find(params[:id])
        record.update!(writable_data)
        record.reload
        render json: { data: BacklogEntryResource.new(record).serializable_hash }
      end

      def destroy
        UserGameBacklog.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      # Validates the pick query params, rendering 422 `invalid_<param>` (the
      # gotm_rounds shape) for the first bad one.
      def pick_options
        source = params[:source].presence || "backlog"
        unless BacklogPicker::SOURCES.include?(source)
          return pick_param_error(:source, "source must be one of #{BacklogPicker::SOURCES.join(', ')}")
        end

        options = { source: }
        {
          platform_id: [ 1, nil ], max_hours: [ 1, 1000 ], seed: [ 0, BacklogPicker::MAX_SEED ], position: [ 0, nil ]
        }.each do |key, (min, max)|
          next if params[key].blank?

          value = Integer(params[key].to_s, 10, exception: false)
          return pick_param_error(key, "#{key} must be an integer #{max ? "from #{min} to #{max}" : "of at least #{min}"}") if value.nil? || value < min || (max && value > max)

          options[key] = value
        end
        options[:seed] ||= SecureRandom.random_number(BacklogPicker::MAX_SEED + 1)
        options
      end

      def pick_param_error(name, message)
        render json: { error: "invalid_#{name}", message: }, status: :unprocessable_content
        nil
      end

      def writable_data
        request_data.slice(*WRITABLE_ATTRS)
      end

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        UserGameBacklog.find_by(entry_id: params[:id])&.user_id
      end
    end
  end
end
