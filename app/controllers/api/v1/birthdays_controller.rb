# frozen_string_literal: true

module Api
  module V1
    # Upcoming Birthdays (spec #396, api#400), for the website's dashboard
    # and the bot's /birthdays. Any signed-in member or the service token.
    # Birthdays are a utility, not a Feature, so nothing gates it.
    class BirthdaysController < ApplicationController
      # GET /api/v1/birthdays/upcoming
      #
      # The shared Birthdays from today through today + 29 days in club days
      # (America/New_York), by date, then display name. See Birthdays::Upcoming.
      def upcoming
        render json: { data: Birthdays::Upcoming.entries(Birthdays.today) }
      end
    end
  end
end
