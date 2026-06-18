# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/regions', type: :request do
  path '/api/v1/regions' do
    get 'List regions' do
      tags 'Regions'
      description 'Returns release regions (NA, JP, EU, ...). Supports exact `code` lookup and `igdb_id` filtering; both ' \
                  'return the paginated list shape (a single match comes back as a one-element list).'
      produces 'application/json'
      parameter name: :code, in: :query, schema: { type: :string }, required: false,
        description: 'Exact `region_code` lookup (e.g. `NA`, `EU`).'
      parameter name: :igdb_id, in: :query, schema: { type: :integer }, required: false,
        description: 'Lookup by IGDB region id (filters on `igdb_region_id`).'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'regions list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Region' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/regions/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbRegion id.'

    get 'Show region' do
      tags 'Regions'
      produces 'application/json'

      response '200', 'region' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Region' } }
      end

      response '404', 'region not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
