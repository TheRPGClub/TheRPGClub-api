# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/themes', type: :request do
  path '/api/v1/themes' do
    get 'List themes' do
      tags 'Themes'
      description 'Returns the IGDB-curated game themes. Supports `q` for case-insensitive name search.'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: false, description: 'Search term against `name`.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'themes list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Theme' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/themes/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbTheme id.'

    get 'Show theme' do
      tags 'Themes'
      produces 'application/json'

      response '200', 'theme' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Theme' } }
      end

      response '404', 'theme not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
