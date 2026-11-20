# frozen_string_literal: true

module Api
  module V1
    # Challenge Activity (spec api#421, ticket api#424): the club-wide feed
    # of recent Challenge happenings, for the dashboard's Challenge Activity
    # panel (Challenges::Activity). Gated by the `challenges` Feature.
    class ChallengeActivityController < ApplicationController
      feature :challenges

      DEFAULT_PER = 10
      MAX_PER = 50

      # GET /api/v1/challenge_activity?per=5
      #
      # Newest first, `per` events (default 10, at most 50); no further pages.
      def index
        per = clamp_per(params[:per], default_per: DEFAULT_PER, max_per: MAX_PER)
        render json: { data: Challenges::Activity.recent(per).map(&:as_json), meta: { per: per } }
      end
    end
  end
end
