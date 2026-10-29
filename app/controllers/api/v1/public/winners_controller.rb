# frozen_string_literal: true

module Api
  module V1
    module Public
      # The recent GOTM / NR-GOTM winners for www's logged-out landing page
      # (cover story hero and winners marquee). Unauthenticated, so it carries
      # club content only: no member data, Reddit URLs or Discord ids.
      class WinnersController < ApplicationController
        skip_before_action :require_authentication!

        ROUNDS = 24

        # GET /api/v1/public/winners
        #
        # The latest ROUNDS rounds' winning games, newest round first, GOTM
        # before NR-GOTM, `game_index` order within a track. Abuse protection
        # is caching only: the payload is cached for 10 minutes, keyed on the
        # latest round number so a new round busts it, and marked publicly
        # cacheable for shared caches.
        def index
          payload = Rails.cache.fetch([ "public_winners", ROUNDS, latest_round_number ], expires_in: 10.minutes) do
            build_payload
          end

          expires_in 10.minutes, public: true
          render json: payload
        end

        private

        def latest_round_number
          [ GotmEntry.maximum(:round_number), NrGotmEntry.maximum(:round_number) ].compact.max
        end

        def build_payload
          history = Gotm::RoundHistory.new
          round_numbers = history.rounds_relation(sort: "desc").limit(ROUNDS).map(&:round_number)
          data = history.winners(round_numbers).map do |kind, entry|
            {
              round_number: entry.round_number,
              month_year: entry.month_year,
              kind: kind,
              game_id: entry.game.game_id,
              title: entry.game.title,
              cover_url: entry.game.cover_url,
              art_url: entry.game.art_url
            }
          end
          { data: data, meta: { rounds: round_numbers.length } }
        end
      end
    end
  end
end
