# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/news_categories', type: :request do
  path '/api/v1/news_categories' do
    get 'List the News Categories' do
      tags 'News Hub'
      description 'The fixed, ordered list of News Categories (spec #355), so the website and the bot never ' \
                  'hard-code their keys or names. Changing the list is an API release. Belongs to the News Hub ' \
                  'Feature: a member who cannot use it gets 404 `not_found`; the service token is not gated. ' \
                  "Keys, in order: #{NewsCategory.keys.map { |key| "`#{key}`" }.join(', ')}. Not paginated."
      produces 'application/json'

      response '200', 'the News Categories, in order' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/NewsCategory' } }
        }, required: %w[data]
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the viewer cannot use the News Hub Feature' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
