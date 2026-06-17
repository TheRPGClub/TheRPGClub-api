# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/social_platforms', type: :request do
  path '/api/v1/social_platforms' do
    get 'List social platforms' do
      tags 'Social Platforms'
      description 'Returns the catalog of social-network platforms users can link on their profile.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'social platforms' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/SocialPlatform' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create or upsert a social platform' do
      tags 'Social Platforms'
      description 'Open to any authenticated caller. Creates a new social platform. `label` ' \
                  'is required and unique (case-insensitive); on a duplicate-label conflict the ' \
                  'existing matching record is returned with status 200 instead of an error. ' \
                  '`created_by_user_id` is set from the authenticated caller and ignored if sent.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              label: { type: :string, description: 'Required. Unique (case-insensitive).' },
              position: { type: :integer, description: 'Sort order. Optional; defaults to 1000.' }
            },
            required: %w[label]
          }
        },
        required: %w[data]
      }

      response '201', 'platform created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SocialPlatform' } }
      end

      response '200', 'duplicate label — returning existing platform' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SocialPlatform' } }
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
