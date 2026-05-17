# frozen_string_literal: true

module Api
  module V1
    class UserSocialsController < ApplicationController
      before_action :require_owner!, only: %i[create update destroy]

      def index
        scope = UserSocial.where(user_id: params[:user_id]).includes(:social_platform)
        render_collection(scope, default_order: { id: :asc })
      end

      def show
        record = UserSocial.includes(:social_platform).find(params[:id])
        render json: { data: serialize(record) }
      end

      def create
        record = UserSocial.create!(request_data.merge("user_id" => params[:user_id]))
        record = UserSocial.includes(:social_platform).find(record.id)
        render json: { data: serialize(record) }, status: :created
      end

      def update
        record = UserSocial.find(params[:id])
        record.update!(request_data)
        record = UserSocial.includes(:social_platform).find(record.id)
        render json: { data: serialize(record) }
      end

      def destroy
        UserSocial.find(params[:id]).destroy!
        render json: { deleted: true }
      end

      private

      def serialize(record)
        record.as_json.merge("social_platform" => record.social_platform.as_json)
      end

      def resolve_owner_id
        return params[:user_id] if params[:user_id].present?
        return nil unless params[:id].present?

        UserSocial.find_by(id: params[:id])&.user_id
      end
    end
  end
end
