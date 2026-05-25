# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/gotm_entries', type: :request do
  path '/api/v1/gotm_entries' do
    get 'List Game of the Month entries' do
      tags 'GOTM'
      description 'Returns GOTM (Game of the Month) entries, newest round first. Use `include=game` to eager-load the related game record and its images.'
      produces 'application/json'
      parameter name: :round_number, in: :query, schema: { type: :integer }, required: false, description: 'Filter to a specific round number.'
      parameter name: :include, in: :query, schema: { type: :string, example: 'game' }, required: false,
        description: 'Comma-separated includes. Currently `game` is supported.'
      parameter name: :limit, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :offset, in: :query, schema: { type: :integer, default: 0 }, required: false
      parameter name: :page, in: :query, schema: { type: :integer, default: 1 }, required: false

      response '200', 'GOTM entries' do
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

  path '/api/v1/gotm_entries/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GotmEntry id.'

    get 'Show a Game of the Month entry' do
      tags 'GOTM'
      produces 'application/json'
      parameter name: :include, in: :query, schema: { type: :string, example: 'game' }, required: false

      response '200', 'GOTM entry' do
        schema type: :object, properties: { data: { type: :object, additionalProperties: true } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
