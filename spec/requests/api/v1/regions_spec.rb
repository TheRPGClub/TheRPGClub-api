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

    post 'Create or upsert a region' do
      tags 'Regions'
      description 'Admin/service-only find-or-create keyed on `igdb_region_id` (the bot\'s `ensureRegion`). ' \
                  'The payload fields map onto the columns: `code` -> region_code, `name` -> region_name, ' \
                  '`igdb_id` -> igdb_region_id. Returns the existing region with 200 when the IGDB id is ' \
                  'already known, or creates it and returns 201. `code`/`name` are applied only on create.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              code: { type: :string, description: 'Internal region code, e.g. `NA` (set only on create).' },
              name: { type: :string, description: 'Region name (set only on create).' },
              igdb_id: { type: :integer, description: 'IGDB region id. Required; the upsert key.' }
            },
            required: %w[igdb_id]
          }
        },
        required: %w[data]
      }

      response '201', 'region created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Region' } }
      end

      response '200', 'existing region (matched on IGDB id)' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Region' } }
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
