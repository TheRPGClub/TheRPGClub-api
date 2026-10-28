# frozen_string_literal: true

module Api
  module V1
    class UserSocialsController < ApplicationController
      before_action :require_owner!, only: %i[create update destroy]

      # Caller-settable columns. `user_id` comes from the path (or the existing
      # record) and the key is generated, so neither is accepted in the body.
      WRITABLE_ATTRS = %w[platform_id url display_text].freeze

      def index
        scope = UserSocial.where(user_id: params[:user_id]).includes(:social_platform)
        render_collection(scope, resource: UserSocialResource, default_order: { id: :asc })
      end

      def show
        record = UserSocial.includes(:social_platform).find(params[:id])
        render json: { data: UserSocialResource.new(record).serializable_hash }
      end

      def create
        record = UserSocial.create!(writable_data.merge("user_id" => params[:user_id]))
        record = UserSocial.includes(:social_platform).find(record.id)
        render json: { data: UserSocialResource.new(record).serializable_hash }, status: :created
      end

      def update
        record = UserSocial.find(params[:id])
        record.update!(writable_data)
        record = UserSocial.includes(:social_platform).find(record.id)
        render json: { data: UserSocialResource.new(record).serializable_hash }
      end

      def destroy
        UserSocial.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      def writable_data
        request_data.slice(*WRITABLE_ATTRS)
      end

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        UserSocial.find_by(id: params[:id])&.user_id
      end
    end
  end
end
