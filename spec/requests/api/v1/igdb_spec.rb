# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/igdb', type: :request do
  path '/api/v1/igdb/search' do
    get 'Search IGDB for games' do
      tags 'IGDB'
      description 'Admin/service-only. Returns IGDB game candidates so a caller can pick the right ' \
                  '`igdb_id` to import via `POST /api/v1/games`. Two modes, selected by param: pass ' \
                  '`igdb_id` to look games up directly by id (single or comma-separated), or `q` for a ' \
                  'fuzzy title search. Either accepts several values to seed a bulk import — ' \
                  '`igdb_id=1,2,3` or repeated `q[]=zelda&q[]=mario` (max 10, IGDB\'s multiquery cap). ' \
                  'Multi-title results are deduped by `igdb_id` and each carries `matched_query` (the ' \
                  'searched title it matched). Every candidate carries `already_imported` (whether a ' \
                  'local game with that `igdb_id` already exists) so the UI can offer "view" vs ' \
                  '"import". An empty `igdb_id` and a blank `q` both return an empty list.'
      produces 'application/json'
      parameter name: :q, in: :query, required: false, explode: true, style: :form,
        schema: { type: :array, items: { type: :string } },
        description: 'Title(s) to search for; repeat to search several at once (`q[]=zelda&q[]=mario`, ' \
                     'max 10). Ignored when `igdb_id` is given.'
      parameter name: :igdb_id, in: :query, schema: { type: :string }, required: false,
        description: 'IGDB id(s) to look up directly, e.g. `1234` or `1,2,3`. Takes precedence over `q`.'
      parameter name: :per, in: :query, schema: { type: :integer, default: 25, maximum: 50 }, required: false,
        description: 'Max candidates to return (capped at 50; per title in a multi-title search). ' \
                     '`limit` is accepted as an alias. Defaults to the number of ids for an `igdb_id` lookup.'

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
                matched_query: { type: :string, nullable: true,
                  description: 'The searched title this candidate matched. Present only for multi-title searches.' },
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

      response '422', 'IGDB not configured, or more than 10 titles requested' do
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
