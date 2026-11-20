# frozen_string_literal: true

module Api
  module V1
    # A member's Hidden Platforms (spec api#421, ticket api#427; GLOSSARY.md
    # "Hidden Platform"): the platforms they leave out of their own Release
    # Calendar and Upcoming Releases panel (UpcomingReleasesController#index).
    # Part of the Release Calendar Feature.
    #
    # Only the member themself may read or change it. Hidden Platforms only
    # shape the website, so the bot's service token is refused too, as for
    # News Category Preferences.
    class HiddenPlatformsController < ApplicationController
      feature :release_calendar

      INVALID = "platform_ids must be a list of platform ids"

      before_action :refuse_service!
      before_action :require_owner!

      # GET /api/v1/users/:user_id/hidden_platforms
      def show
        render json: { data: document(params[:user_id]) }
      end

      # PUT /api/v1/users/:user_id/hidden_platforms
      # Body: { "data": { "platform_ids": [<platform id>, ...] } }
      # Replaces the member's whole set; an empty list clears it. An id sent
      # twice counts once. An unknown platform refuses the whole change with 422.
      def update
        ids = request_data["platform_ids"]
        error = platform_ids_error(ids)
        return render(json: { error: error }, status: :unprocessable_content) if error

        user = RpgClubUser.find_or_create_by!(user_id: params[:user_id])
        replace(user, ids.uniq)

        render json: { data: document(user.user_id) }
      end

      private

      # require_owner! lets the service token act as any member; Hidden
      # Platforms are the member's own, so it is refused here first.
      def refuse_service!
        gate_or_forbid(!current_principal.service?)
      end

      def platform_ids_error(ids)
        return INVALID unless ids.is_a?(Array) && ids.all? { |id| id.is_a?(Integer) && id.positive? }

        known = GamedbPlatform.where(platform_id: ids).pluck(:platform_id)
        missing = ids.find { |id| known.exclude?(id) }
        "unknown platform: #{missing}" if missing
      end

      # The member's row lock serialises two saves at once, so each replaces
      # the set whole.
      def replace(user, ids)
        MemberHiddenPlatform.transaction do
          user.lock!
          MemberHiddenPlatform.where(user_id: user.user_id).delete_all
          rows = ids.map { |id| { user_id: user.user_id, platform_id: id, created_at: Time.current } }
          MemberHiddenPlatform.insert_all!(rows) if rows.any?
        end
      end

      def document(user_id)
        platforms = GamedbPlatform.where(platform_id: MemberHiddenPlatform.platform_ids_for(user_id))
          .order(:platform_name, :platform_id)
          .map { |platform| platform.slice(:platform_id, :platform_name, :platform_abbreviation) }
        { user_id: user_id, platform_ids: platforms.pluck("platform_id"), platforms: platforms }
      end
    end
  end
end
