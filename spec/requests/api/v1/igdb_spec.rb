# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/igdb', type: :request do
  path '/api/v1/igdb/search' do
    get 'Search IGDB for games' do
      tags 'IGDB'
      description 'Admin/service-only. Proxies an IGDB games title search and returns candidates so a ' \
                  'caller can pick the right `igdb_id` to import via `POST /api/v1/games`. Each candidate ' \
                  'carries `already_imported` (whether a local game with that `igdb_id` already exists) so ' \
                  'the UI can offer "view" vs "import". A blank `q` returns an empty list.'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: true,
        description: 'Title to search for.'
      parameter name: :per, in: :query, schema: { type: :integer, default: 25, maximum: 50 }, required: false,
        description: 'Max candidates to return (capped at 50). `limit` is accepted as an alias.'

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
