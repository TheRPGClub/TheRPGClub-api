# frozen_string_literal: true

module Api
  module V1
    class UsersController < ApplicationController
      skip_before_action :require_authentication!, only: %i[avatar profile_image]

      def index
        scope = RpgClubUser.without_images
        scope = scope.where("username ILIKE :term OR global_name ILIKE :term OR user_id = :exact", term: "%#{query}%", exact: params[:q]) if params[:q].present?
        render_collection(scope, default_order: { username: :asc })
      end

      def show
        model = RpgClubUser.includes(socials: :social_platform).find(params[:user_id])
        user = RpgClubUser.without_images.find(params[:user_id]).as_json
        socials = model.socials.map do |social|
          social.as_json.merge("social_platform" => social.social_platform.as_json)
        end

        render json: {
          data: user.merge(
            "membership" => model.membership,
            "socials"    => socials
          )
        }
      end

      def avatar
        send_user_image("avatar_blob")
      end

      def profile_image
        send_user_image("profile_image")
      end

      private

      def query
        ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.strip)
      end

      def send_user_image(column)
        data = RpgClubUser.select(column).find(params[:user_id]).public_send(column)
        return render(json: { error: "image_not_found" }, status: :not_found) if data.blank?

        send_data data, type: "image/png", disposition: "inline"
      end
    end
  end
end
