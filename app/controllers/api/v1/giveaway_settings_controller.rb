# frozen_string_literal: true

module Api
  module V1
    # A donor's notify-on-claim preference (issue #95), exposed as a small
    # document over the user's `donor_notify_on_claim` column rather than the
    # whole user record. GET reads it (open, like the other user sub-resource
    # reads); PATCH updates it (owner-only).
    #
    # Both endpoints mirror the bot's semantics: GET defaults to `false` for an
    # unknown user (the bot reads `?? false`), and PATCH upserts — creating the
    # user row when absent — so a donor can set the flag before any other write
    # has materialized their row.
    class GiveawaySettingsController < ApplicationController
      before_action :require_owner!, only: :update

      # GET /api/v1/users/:user_id/giveaway_settings
      def show
        notify = RpgClubUser.where(user_id: params[:user_id]).pick(:donor_notify_on_claim)
        render json: { data: settings(params[:user_id], notify) }
      end

      # PATCH /api/v1/users/:user_id/giveaway_settings
      # Body: { "data": { "notify_on_claim": true|false } }
      def update
        notify = request_data["notify_on_claim"]
        if notify.nil?
          return render json: { error: "notify_on_claim required" }, status: :unprocessable_entity
        end

        user = RpgClubUser.find_or_initialize_by(user_id: params[:user_id])
        user.update!(donor_notify_on_claim: ActiveModel::Type::Boolean.new.cast(notify))

        render json: { data: settings(user.user_id, user.donor_notify_on_claim) }
      end

      private

      # The preference as the 2-field document the consumer expects, renaming the
      # column to the API's `notify_on_claim` and coercing a nil (unknown user)
      # to false.
      def settings(user_id, notify_on_claim)
        { user_id: user_id, notify_on_claim: !!notify_on_claim }
      end
    end
  end
end
