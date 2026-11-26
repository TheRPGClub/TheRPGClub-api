# frozen_string_literal: true

module Api
  module V1
    # A member's News Mark (spec api#494, ticket api#495): the moment up to
    # which they have seen the News Hub. The News page reads it to split new
    # News Items from seen ones, moves it forward when the member leaves the
    # page, and moves it to now for Mark all seen.
    #
    # Only the member themself may read or set it. The News Mark only shapes
    # the website, so the bot's service token is refused too.
    class NewsMarksController < ApplicationController
      feature :news_hub

      before_action :refuse_service!
      before_action :require_owner!

      # GET /api/v1/users/:user_id/news_mark
      def show
        render json: { data: document(NewsMark.for(params[:user_id])) }
      end

      # PUT /api/v1/users/:user_id/news_mark
      # Body: { "data": { "news_mark": "<ISO 8601 instant>" } }
      #    or { "data": { "all_seen": true } } (Mark all seen: now)
      # Moves the News Mark forward. An instant before the stored mark keeps
      # the stored one; an instant past now is clamped to now. Returns the
      # stored mark.
      def update
        instant, error = requested_instant
        return render(json: { error: error }, status: :unprocessable_content) if error

        render json: { data: document(NewsMark.advance!(params[:user_id], instant)) }
      end

      private

      # require_owner! lets the service token act as any member; the News
      # Mark is the member's own, so it is refused here first.
      def refuse_service!
        gate_or_forbid(!current_principal.service?)
      end

      def requested_instant
        data = request_data
        all_seen = data["all_seen"]
        mark = data["news_mark"]
        return [ nil, "give either news_mark or all_seen, not both" ] if data.key?("all_seen") && data.key?("news_mark")
        return [ Time.current, nil ] if all_seen == true
        return [ nil, "all_seen must be true" ] if data.key?("all_seen")
        return [ nil, "news_mark or all_seen required" ] if mark.nil?

        [ Time.iso8601(mark.to_s), nil ]
      rescue ArgumentError
        [ nil, "news_mark must be an ISO 8601 instant" ]
      end

      def document(mark)
        { user_id: params[:user_id], news_mark: mark&.utc&.iso8601(6) }
      end
    end
  end
end
