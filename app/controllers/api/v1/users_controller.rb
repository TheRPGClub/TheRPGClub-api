# frozen_string_literal: true

module Api
  module V1
    class UsersController < ApplicationController
      skip_before_action :require_authentication!, only: %i[avatar profile_image]

      PREVIEW_LIMIT_DEFAULT = 10
      PREVIEW_LIMIT_MAX = 50

      def index
        scope = RpgClubUser.without_images
        scope = scope.where("username ILIKE :term OR global_name ILIKE :term OR user_id = :exact", term: "%#{query}%", exact: params[:q]) if params[:q].present?
        render_collection(scope, resource: UserSummaryResource, default_order: { username: :asc })
      end

      def show
        user = RpgClubUser.without_images.includes(socials: :social_platform).find(params[:user_id])
        limit = preview_limit

        socials = user.socials.map do |social|
          social.as_json.merge("social_platform" => social.social_platform.as_json)
        end

        now_playing = user.now_playing_entries.preload(:game, :platform).order(added_at: :desc).limit(limit).to_a
        favorites   = user.game_favorites.preload(:game).order(:sort_order).limit(limit).to_a
        reviews     = user.reviews.preload(:game).order(created_at: :desc).limit(limit).to_a
        completions = user.game_completions.preload(:game, :platform).order(completed_at: :desc).limit(limit).to_a

        counts = {
          now_playing: user.now_playing_entries.count,
          favorites:   user.game_favorites.count,
          reviews:     user.reviews.count,
          completions: user.game_completions.count,
          backlog:     user.game_backlog_entries.count,
          collections: user.game_collections.count
        }

        render json: {
          data: user.as_json.merge(
            "membership"  => user.membership,
            "socials"     => socials,
            "now_playing" => NowPlayingEntryResource.new(now_playing).serializable_hash,
            "favorites"   => FavoriteEntryResource.new(favorites).serializable_hash,
            "reviews"     => ReviewEntryResource.new(reviews).serializable_hash,
            "completions" => CompletionEntryResource.new(completions).serializable_hash,
            "counts"      => counts
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

      def preview_limit
        raw = params[:preview_limit].to_i
        raw = PREVIEW_LIMIT_DEFAULT if raw <= 0
        [ raw, PREVIEW_LIMIT_MAX ].min
      end

      def send_user_image(column)
        data = RpgClubUser.select(column).find(params[:user_id]).public_send(column)
        return render(json: { error: "image_not_found" }, status: :not_found) if data.blank?

        send_data data, type: "image/png", disposition: "inline"
      end
    end
  end
end
