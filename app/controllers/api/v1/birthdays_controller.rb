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
      # (America/New_York), by date, then display name, and `next`: the first
      # shared Birthday after that, without the member (null when none). See
      # Birthdays::Upcoming.
      def upcoming
        today = ClubDay.today
        render json: { data: Birthdays::Upcoming.entries(today), next: Birthdays::Upcoming.next_beyond(today) }
      end
    end
  end
end
