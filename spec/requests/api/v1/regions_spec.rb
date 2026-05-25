# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/regions', type: :request do
  path '/api/v1/regions' do
    get 'List regions' do
      tags 'Regions'
      description 'Returns release regions (NA, JP, EU, ...).'
      produces 'application/json'
      parameter name: :limit, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :offset, in: :query, schema: { type: :integer, default: 0 }, required: false
      parameter name: :page, in: :query, schema: { type: :integer, default: 1 }, required: false

      response '200', 'regions list' do
        schema type: :object, properties: {
          data: { type: :array, items: { type: :object, additionalProperties: true } },
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
        schema type: :object, properties: { data: { type: :object, additionalProperties: true } }
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
