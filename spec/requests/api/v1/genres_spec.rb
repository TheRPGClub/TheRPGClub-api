# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/genres', type: :request do
  path '/api/v1/genres' do
    get 'List genres' do
      tags 'Genres'
      description 'Returns the IGDB-curated game genres. Supports `q` for case-insensitive name search.'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: false, description: 'Search term against `name`.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'genres list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Genre' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create or upsert a genre' do
      tags 'Genres'
      description 'Admin/service-only find-or-create keyed on `igdb_genre_id` (the bot\'s `ensureGenre`). ' \
                  'Returns the existing genre with 200 when the IGDB id is already known, or creates it and ' \
                  'returns 201. `name` is applied only when a new row is created.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              name: { type: :string, description: 'Genre name (set only on create).' },
              igdb_genre_id: { type: :integer, description: 'IGDB genre id. Required; the upsert key.' }
            },
            required: %w[igdb_genre_id]
          }
        },
        required: %w[data]
      }

      response '201', 'genre created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Genre' } }
      end

      response '200', 'existing genre (matched on IGDB id)' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Genre' } }
      end

      response '403', 'forbidden — caller is not an admin or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed (missing `igdb_genre_id` or blank `name`)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/genres/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbGenre id.'

    get 'Show genre' do
      tags 'Genres'
      produces 'application/json'

      response '200', 'genre' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Genre' } }
      end

      response '404', 'genre not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
