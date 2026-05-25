# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/dashboards', type: :request do
  path '/api/v1/dashboard' do
    get 'Front-page dashboard' do
      tags 'Dashboard'
      description 'Returns the most recent Game of the Month (GOTM) and Non-Retro GOTM entries used to populate the front page.'
      produces 'application/json'
      parameter name: :limit, in: :query, schema: { type: :integer, minimum: 1, maximum: 20, default: 10 }, required: false,
        description: 'Number of entries to return for each list (default 10, max 20).'

      response '200', 'dashboard payload' do
        schema type: :object, properties: {
          data: {
            type: :object,
            properties: {
              gotm: { type: :array, items: { type: :object, additionalProperties: true } },
              nr_gotm: { type: :array, items: { type: :object, additionalProperties: true } }
            }
          },
          meta: {
            type: :object,
            properties: { limit: { type: :integer, example: 10 } }
          }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
