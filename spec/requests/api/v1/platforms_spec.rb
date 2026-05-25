# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/platforms', type: :request do
  path '/api/v1/platforms' do
    get 'List platforms' do
      tags 'Platforms'
      description 'Returns gaming platforms (consoles, PC, mobile, etc.). Supports `q` for case-insensitive name/code search.'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: false, description: 'Search term against `platform_name` or `platform_code`.'
      parameter name: :limit, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :offset, in: :query, schema: { type: :integer, default: 0 }, required: false
      parameter name: :page, in: :query, schema: { type: :integer, default: 1 }, required: false

      response '200', 'platforms list' do
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

  path '/api/v1/platforms/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbPlatform id.'

    get 'Show platform' do
      tags 'Platforms'
      produces 'application/json'

      response '200', 'platform' do
        schema type: :object, properties: { data: { type: :object, additionalProperties: true } }
      end

      response '404', 'platform not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
