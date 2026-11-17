# frozen_string_literal: true

module Api
  module V1
    # A member's Birth Date (spec #376, ticket #380), as a small document over
    # the member's record. See BirthDates for the limit on changing it.
    #
    # Only the member and staff (Moderators and above) may read or set it.
    # The bot calls with the service token and names the member it acts for
    # (`acting_user_id`: a query parameter on GET, `data.acting_user_id` on
    # PUT); the API decides from that member's stored roles whether they are
    # staff (docs/adr/0005). Staff changes skip the limit and don't use up the
    # member's changes.
    class BirthDatesController < ApplicationController
      include ActingMember

      before_action :require_member_or_staff!

      # GET /api/v1/users/:user_id/birth_date
      def show
        user = RpgClubUser.without_images.find_by(user_id: params[:user_id])
        render json: { data: BirthDates.document(params[:user_id], user) }
      end

      # PUT /api/v1/users/:user_id/birth_date
      # Body: { "data": { "birth_date": "1990-05-04" | null, "acting_user_id": "..." } }
      #
      # Sets the Birth Date, or removes it with null. A member's third change
      # in a calendar month is refused with 422 and `next_change_on`, the first
      # day of next month.
      def update
        data = params.require(:data)
        return render(json: { error: "birth_date required" }, status: :unprocessable_content) unless data.key?(:birth_date)

        user = own? ? RpgClubUser.find_or_create_by!(user_id: params[:user_id].to_s) : RpgClubUser.find(params[:user_id])
        BirthDates.change!(user, data[:birth_date], by: acting_user_id, staff: staff?)

        render json: { data: BirthDates.document(user.user_id, user) }
      rescue BirthDates::Invalid => e
        render json: { error: e.message }, status: :unprocessable_content
      rescue BirthDates::LimitReached => e
        render json: { error: e.message, next_change_on: e.next_change_on.iso8601 }, status: :unprocessable_content
      end

      private

      # The member themself, or a Moderator and above. The bot must name the
      # member it acts for.
      def require_member_or_staff!
        if current_principal.service? && acting_user_id.blank?
          return render(json: { error: "acting_user_id required" }, status: :bad_request)
        end

        gate_or_forbid(own? || staff?)
      end

      def own?
        acting_user_id.present? && acting_user_id == params[:user_id].to_s
      end

      # Moderator or above: by the session for a signed-in member, by the
      # acting member's stored roles for the bot.
      def staff?
        return @staff if defined?(@staff)

        @staff = current_principal.service? ? acting_member&.moderator_or_above? == true : moderator_or_above?
      end
    end
  end
end
