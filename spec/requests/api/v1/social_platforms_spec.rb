# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/social_platforms', type: :request do
  path '/api/v1/social_platforms' do
    get 'List social platforms' do
      tags 'Social Platforms'
      description 'Returns the catalog of social-network platforms users can link on their profile.'
      produces 'application/json'
      parameter name: :limit, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :offset, in: :query, schema: { type: :integer, default: 0 }, required: false
      parameter name: :page, in: :query, schema: { type: :integer, default: 1 }, required: false

      response '200', 'social platforms' do
        schema type: :object, properties: {
          data: { type: :array, items: { type: :object, additionalProperties: true } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create or upsert a social platform' do
      tags 'Social Platforms'
      description 'Creates a new social platform. If a unique-label conflict is raised, the existing matching record is returned with status 200 instead of an error.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            additionalProperties: true,
            description: 'SocialPlatform attributes (`label`, `icon`, `position`, etc.).'
          }
        },
        required: %w[data]
      }

      response '201', 'platform created' do
        schema type: :object, properties: { data: { type: :object, additionalProperties: true } }
      end

      response '200', 'duplicate label — returning existing platform' do
        schema type: :object, properties: { data: { type: :object, additionalProperties: true } }
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
