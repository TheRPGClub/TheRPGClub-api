# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/igdb', type: :request do
  path '/api/v1/igdb/search' do
    get 'Search IGDB for games' do
      tags 'IGDB'
      description 'Admin/service-only. Returns IGDB game candidates so a caller can pick the right ' \
                  '`igdb_id` to import via `POST /api/v1/games`. Two modes, selected by param: pass ' \
                  '`igdb_id` to look games up directly by id (single or comma-separated), or `q` for a ' \
                  'fuzzy title search. Each candidate carries `already_imported` (whether a local game ' \
                  'with that `igdb_id` already exists) so the UI can offer "view" vs "import". An empty ' \
                  '`igdb_id` and a blank `q` both return an empty list.'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: false,
        description: 'Title to search for. Ignored when `igdb_id` is given.'
      parameter name: :igdb_id, in: :query, schema: { type: :string }, required: false,
        description: 'IGDB id(s) to look up directly, e.g. `1234` or `1,2,3`. Takes precedence over `q`.'
      parameter name: :per, in: :query, schema: { type: :integer, default: 25, maximum: 50 }, required: false,
        description: 'Max candidates to return (capped at 50). `limit` is accepted as an alias. ' \
                     'Defaults to the number of ids for an `igdb_id` lookup.'

      response '200', 'IGDB candidates' do
        schema type: :object, properties: {
          data: {
            type: :array,
            items: {
              type: :object,
              properties: {
                igdb_id: { type: :integer, example: 1234 },
                name: { type: :string },
                slug: { type: :string, nullable: true },
                summary: { type: :string, nullable: true },
                url: { type: :string, nullable: true },
                total_rating: { type: :number, nullable: true },
                first_release_date: { type: :string, nullable: true, description: 'ISO 8601 timestamp.' },
                cover_url: { type: :string, nullable: true },
                already_imported: { type: :boolean }
              },
              required: %w[igdb_id name already_imported]
            }
          }
        }
      end

      response '403', 'forbidden — admin or service required' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'IGDB not configured' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '502', 'IGDB request failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
