# frozen_string_literal: true

module Api
  module V1
    # The signed-in Member's Theme (spec api#523, ticket api#524;
    # docs/adr/0017). Named MemberThemes because ThemesController serves
    # GameDB's IGDB themes.
    #
    # Not behind the Themes Feature gate: returning to the default is always
    # allowed. Which Themes the Member may choose is Themes::Choice's call.
    # A Theme only shapes the website, so the bot's service token is refused.
    class MemberThemesController < ApplicationController
      before_action :refuse_service!

      # PUT /api/v1/me/theme
      # Body: { "theme": "<Theme key>" | null }
      # Stores the Member's Theme; null returns them to the club default.
      # An unknown key is 422, a Theme they may not choose 403, and neither
      # changes anything. Returns the session's theme fields.
      def update
        raise ActionController::ParameterMissing, :theme unless params.key?(:theme)

        key = params[:theme]
        unless key.nil? || Themes.known?(key)
          return render(json: { error: "unknown Theme: #{key}" }, status: :unprocessable_content)
        end

        user = RpgClubUser.without_images.find_by(user_id: current_principal.id.to_s)
        return render(json: { error: "not_found" }, status: :not_found) unless user

        access = Features::Access.for_viewer(user, staff: admin_or_above?)
        if key && !Themes::Choice.new(access, nil).available?(key)
          return render(json: { error: "forbidden" }, status: :forbidden)
        end

        user.update_columns(theme: key)
        render json: Themes::Choice.new(access, key).document
      end

      private

      def refuse_service!
        gate_or_forbid(current_principal.discord_user?)
      end
    end
  end
end
