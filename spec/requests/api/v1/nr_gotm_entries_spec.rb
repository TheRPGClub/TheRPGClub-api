# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/nr_gotm_entries', type: :request do
  path '/api/v1/nr_gotm_entries' do
    get 'List Non-Retro Game of the Month entries' do
      tags 'Non-Retro GOTM'
      description 'Returns Non-Retro GOTM entries, newest round first. Use `include=game` to eager-load the related game record and its images.'
      produces 'application/json'
      parameter name: :round_number, in: :query, schema: { type: :integer }, required: false
      parameter name: :include, in: :query, schema: { type: :string, example: 'game' }, required: false
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'Non-Retro GOTM entries' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/NrGotmEntry' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/nr_gotm_entries/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'NrGotmEntry id.'

    get 'Show a Non-Retro GOTM entry' do
      tags 'Non-Retro GOTM'
      produces 'application/json'
      parameter name: :include, in: :query, schema: { type: :string, example: 'game' }, required: false

      response '200', 'Non-Retro GOTM entry' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/NrGotmEntry' } }
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
