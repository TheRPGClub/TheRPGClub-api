# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/gotm_rounds', type: :request do
  path '/api/v1/gotm_rounds' do
    get 'List GOTM history by round' do
      tags 'GOTM'
      description 'GOTM and NR-GOTM history grouped by round. Pages are rounds, not entries. Filters apply to ' \
                  'each kind\'s block within a round: `year` matches the trailing year of `month_year`, and `q` ' \
                  'keeps a block (with all its games) when any of its game titles match. NR-GOTM "N/A" ' \
                  'placeholder games are omitted. `meta.years` lists every year for the selected kind(s), ' \
                  'newest first, regardless of the `year` and `q` filters.'
      produces 'application/json'
      parameter name: :kind, in: :query, required: false,
        schema: { type: :string, enum: Gotm::RoundHistory::KIND_PARAMS, default: 'both' }
      parameter name: :year, in: :query, required: false, schema: { type: :integer, example: 2024 },
        description: 'Only rounds whose `month_year` ends in this year.'
      parameter name: :q, in: :query, required: false, schema: { type: :string },
        description: 'Case-insensitive title search over each round block\'s games.'
      parameter name: :sort, in: :query, required: false,
        schema: { type: :string, enum: Gotm::RoundHistory::SORTS, default: 'desc' },
        description: 'Round number order.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 12, maximum: 100 }, required: false,
        description: 'Rounds per page.'

      response '200', 'GOTM rounds' do
        schema type: :object, required: %w[data meta], properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/GotmRound' } },
          meta: {
            allOf: [
              { '$ref' => '#/components/schemas/PaginationMeta' },
              { type: :object, required: %w[years], properties: {
                years: { type: :array, items: { type: :integer }, example: [ 2025, 2024 ] }
              } }
            ]
          }
        }
      end

      response '422', 'invalid `kind`, `sort` or `year`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/gotm_rounds/current' do
    get 'Show the current GOTM round' do
      tags 'GOTM'
      description 'The highest GOTM round plus the NR-GOTM games of that same round (null when it has none), ' \
                  'in the `gotm_rounds` shape. This is the latest round with winners, not the round being ' \
                  'voted on. 404 when there are no GOTM entries.'
      produces 'application/json'

      response '200', 'current GOTM round' do
        schema type: :object, required: %w[data], properties: {
          data: { '$ref' => '#/components/schemas/GotmRound' }
        }
      end

      response '404', 'no GOTM rounds' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
