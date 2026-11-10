# frozen_string_literal: true

module Api
  module V1
    # The News Categories (spec #355), in order, so the website and the bot
    # never hard-code their keys or names. Gated by the News Hub Feature.
    class NewsCategoriesController < ApplicationController
      feature :news_hub

      # GET /api/v1/news_categories
      def index
        render json: { data: NewsCategory.all.map(&:to_h) }
      end
    end
  end
end
