# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/nominations', type: :request do
  path '/api/v1/gotm_entries/{round}/nominations' do
    parameter name: :round, in: :path, schema: { type: :integer }, required: true,
      description: 'GOTM voting round number.'

    get 'List GOTM nominations for a round' do
      tags 'GOTM'
      description 'The games nominated for the given GOTM voting round, oldest first, each ' \
                  'with its embedded nominator (`user`) and `game`.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'GOTM nominations' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Nomination' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/nr_gotm_entries/{round}/nominations' do
    parameter name: :round, in: :path, schema: { type: :integer }, required: true,
      description: 'Non-RPG GOTM voting round number.'

    get 'List Non-RPG GOTM nominations for a round' do
      tags 'GOTM'
      description 'The games nominated for the given Non-RPG GOTM voting round, oldest first, ' \
                  'each with its embedded nominator (`user`) and `game`.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'Non-RPG GOTM nominations' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Nomination' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
