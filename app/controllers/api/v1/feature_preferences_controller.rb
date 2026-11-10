# frozen_string_literal: true

module Api
  module V1
    # A member's Feature Preferences (spec #347, ticket #352): the hideable
    # Features they hid from their own view of the website, and, for staff,
    # the "show Preview features" setting. A small document over the member's
    # stored preferences, in the shape of GiveawaySettingsController.
    #
    # Only the member themself may read or change it. Preferences only shape
    # the website, so the bot's service token is refused too.
    class FeaturePreferencesController < ApplicationController
      before_action :require_self!

      # GET /api/v1/users/:user_id/feature_preferences
      def show
        user = RpgClubUser.find_by(user_id: params[:user_id])
        render json: { data: document(params[:user_id], user) }
      end

      # PATCH /api/v1/users/:user_id/feature_preferences
      # Body: { "data": { "hidden": { "<feature key>": true|false, ... },
      #                   "show_preview_features": true|false } }
      # Both fields are optional, but one is required. `hidden` hides (true) or
      # shows (false) each named Feature and leaves the others untouched.
      # `show_preview_features` is for staff only. Any invalid part refuses the
      # whole change with 422.
      def update
        data = request_data
        hidden = data["hidden"]
        show_preview = data["show_preview_features"]
        return unprocessable("hidden or show_preview_features required") if hidden.nil? && show_preview.nil?

        error = (hidden_error(hidden) unless hidden.nil?) || (show_preview_error(show_preview) unless show_preview.nil?)
        return unprocessable(error) if error

        user = RpgClubUser.find_or_create_by!(user_id: params[:user_id])
        RpgClubUser.transaction do
          (hidden || {}).each do |key, hide|
            scope = MemberFeaturePreference.where(user_id: user.user_id, feature_key: key)
            hide ? scope.first_or_create! : scope.delete_all
          end
          user.update!(show_preview_features: show_preview) unless show_preview.nil?
        end

        render json: { data: document(user.user_id, user) }
      end

      private

      def require_self!
        return if current_principal.discord_user? && current_principal.discord_id.to_s == params[:user_id].to_s

        render json: { error: "forbidden" }, status: :forbidden
      end

      def hidden_error(hidden)
        return "hidden must be an object of Feature keys to true or false" unless hidden.is_a?(Hash)

        hidden.each do |key, hide|
          feature = Features.find(key)
          return "unknown Feature: #{key}" unless feature
          return "hidden.#{key} must be true or false" unless [ true, false ].include?(hide)
          return "#{key} is a Core Feature and cannot be hidden" if hide && feature.core?
        end
        nil
      end

      def show_preview_error(show_preview)
        return "show_preview_features is only for Admins and Superadmins" unless admin_or_above?

        "show_preview_features must be true or false" unless [ true, false ].include?(show_preview)
      end

      def unprocessable(error)
        render json: { error: error }, status: :unprocessable_content
      end

      # `show_preview_features` is null for anyone but staff, whom it does not
      # affect.
      def document(user_id, user)
        access = Features::Access.for_viewer(user, staff: admin_or_above?)
        {
          user_id: user_id,
          hidden: access.hidden_keys,
          show_preview_features: access.staff? ? (user.nil? || user.show_preview_features) : nil,
          features: access.preference_features
        }
      end
    end
  end
end
