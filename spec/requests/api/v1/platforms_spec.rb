# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/platforms', type: :request do
  path '/api/v1/platforms' do
    get 'List platforms' do
      tags 'Platforms'
      description 'Returns gaming platforms (consoles, PC, mobile, etc.). Supports `q` for case-insensitive name/code search, ' \
                  'exact `code` lookup, and IGDB-id filtering via `igdb_ids[]` / `igdb_id`. All filters return the paginated ' \
                  'list shape (a single matching platform comes back as a one-element list).'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: false, description: 'Search term against `platform_name` or `platform_code`.'
      parameter name: :code, in: :query, schema: { type: :string }, required: false,
        description: 'Exact `platform_code` lookup (e.g. `PS5`, `SWITCH`).'
      parameter name: 'igdb_ids[]', in: :query, required: false, explode: true, style: :form,
        schema: { type: :array, items: { type: :integer } },
        description: 'Filter to platforms with any of these `igdb_platform_id`s. Repeat the param: `igdb_ids[]=6&igdb_ids[]=48`.'
      parameter name: :igdb_id, in: :query, schema: { type: :integer }, required: false,
        description: 'Single-id convenience form of `igdb_ids[]` (filters on `igdb_platform_id`).'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'platforms list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Platform' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create or upsert a platform' do
      tags 'Platforms'
      description 'Admin/service-only find-or-create keyed on `igdb_platform_id` (the bot\'s `ensurePlatform`). ' \
                  'The payload fields map onto the columns: `code` -> platform_code, `name` -> platform_name, ' \
                  '`igdb_id` -> igdb_platform_id. Returns the existing platform with 200 when the IGDB id is ' \
                  'already known, or creates it and returns 201. `code`/`name` are applied only on create.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              code: { type: :string, description: 'Internal platform code, e.g. `PS5` (set only on create).' },
              name: { type: :string, description: 'Platform name (set only on create).' },
              igdb_id: { type: :integer, description: 'IGDB platform id. Required; the upsert key.' }
            },
            required: %w[igdb_id]
          }
        },
        required: %w[data]
      }

      response '201', 'platform created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Platform' } }
      end

      response '200', 'existing platform (matched on IGDB id)' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Platform' } }
      end

      response '403', 'forbidden — caller is not an admin or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed (missing `igdb_id` or blank `code`/`name`)' do
        schema '$ref' => '#/components/schemas/Error'
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
      description 'Returns the full platform record (all columns, including the IGDB ' \
                  'bookkeeping fields the list response trims).'
      produces 'application/json'

      response '200', 'platform' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/PlatformDetail' } }
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
