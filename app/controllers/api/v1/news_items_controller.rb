# frozen_string_literal: true

module Api
  module V1
    # News Items (spec #355, ticket #356). The bot records and removes them
    # with the service token as members post, edit and delete messages in the
    # News Categories' threads; members read them as a feed. Gated by the
    # News Hub Feature (the service token is never stopped by the gate).
    class NewsItemsController < ApplicationController
      feature :news_hub

      before_action :require_service!, only: %i[update destroy]

      # GET /api/v1/news_items?category=releases,industry&page=1&per=50
      #
      # The News Items that have a News Category, newest first. `category`
      # narrows to those News Categories (comma-separated, or repeated as
      # `category[]`); an unknown key is a 400.
      def index
        categories = category_filter
        return if performed?

        scope = NewsItem.listed
        scope = scope.where(category_key: categories) if categories.any?
        scope = search(scope)
        pagy, items = pagy(scope.order(posted_at: :desc, id: :desc), **pagy_options)
        items = items.to_a

        render json: {
          data: NewsItemResource.new(items, params: { authors: NewsItemResource.authors_for(items) }).serializable_hash,
          meta: pagy_meta(pagy)
        }
      end

      # PUT /api/v1/news_items/:message_id
      #
      # Records the message as a News Item (201) or updates the one already
      # recorded (200). See NewsItem.record!.
      def update
        item, created = NewsItem.record!(params[:message_id], item_params)
        render json: { data: NewsItemResource.new(item, params: { authors: NewsItemResource.authors_for([ item ]) })
          .serializable_hash }, status: created ? :created : :ok
      end

      # DELETE /api/v1/news_items/:message_id
      #
      # Removes the News Item for good. 204 whether or not it was recorded,
      # so the bot never has to know what the API holds.
      def destroy
        NewsItem.where(message_id: params[:message_id].to_s).delete_all
        head :no_content
      end

      private

      def item_params
        data = params.require(:data)
        raise ActionController::ParameterMissing, "data (object)" unless data.respond_to?(:permit)

        data.permit(:channel_id, :category_key, :author_id, :author_name, :comment, :posted_at, :edited_at,
          link: NewsItem::LINK_FIELDS, images: %i[url expires_at]).to_h
      end

      # Narrows to the News Items whose link title or comment contains `q`,
      # ignoring case. A blank `q` searches nothing.
      def search(scope)
        text = params[:q].to_s.strip
        return scope if text.empty?

        scope.where("link_title ILIKE :q OR comment ILIKE :q", q: "%#{NewsItem.sanitize_sql_like(text)}%")
      end

      # The requested News Category keys; [] when none. Renders 400 and
      # returns [] for an unknown key.
      def category_filter
        keys = Array(params[:category]).flat_map { |value| value.to_s.split(",") }.map(&:strip).compact_blank.uniq
        unknown = keys - NewsCategory.keys
        return keys if unknown.empty?

        render json: { error: "unknown category: #{unknown.join(', ')}" }, status: :bad_request
        []
      end
    end
  end
end
