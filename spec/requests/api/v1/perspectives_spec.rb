# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/perspectives', type: :request do
  path '/api/v1/perspectives' do
    get 'List perspectives' do
      tags 'Perspectives'
      description 'Returns the IGDB-curated player perspectives (first-person, top-down, ...). ' \
                  'Supports `q` for case-insensitive name search.'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: false, description: 'Search term against `name`.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'perspectives list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Perspective' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create or upsert a perspective' do
      tags 'Perspectives'
      description 'Admin/service-only find-or-create keyed on `igdb_perspective_id` (the bot\'s `ensurePerspective`). ' \
                  'Returns the existing perspective with 200 when the IGDB id is already known, or creates it and ' \
                  'returns 201. `name` is applied only when a new row is created.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              name: { type: :string, description: 'Perspective name (set only on create).' },
              igdb_perspective_id: { type: :integer, description: 'IGDB player-perspective id. Required; the upsert key.' }
            },
            required: %w[igdb_perspective_id]
          }
        },
        required: %w[data]
      }

      response '201', 'perspective created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Perspective' } }
      end

      response '200', 'existing perspective (matched on IGDB id)' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Perspective' } }
      end

      response '403', 'forbidden — caller is not an admin or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed (missing `igdb_perspective_id` or blank `name`)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/perspectives/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbPerspective id.'

    get 'Show perspective' do
      tags 'Perspectives'
      produces 'application/json'

      response '200', 'perspective' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Perspective' } }
      end

      response '404', 'perspective not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
