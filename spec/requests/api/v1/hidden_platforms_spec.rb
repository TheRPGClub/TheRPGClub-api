# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/hidden_platforms', type: :request do
  path '/api/v1/users/{user_id}/hidden_platforms' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord user id of the member. Must be the signed-in member.'

    get 'Show a member\'s Hidden Platforms' do
      tags 'Release Calendar'
      description 'The platforms the member leaves out of their own Release Calendar and Upcoming Releases ' \
                  'panel (`GET /upcoming_releases`), in platform name order. Empty until they hide one. Only ' \
                  'the member themself may read it; another member, staff and the bot\'s service token get ' \
                  '403. Belongs to the Release Calendar Feature, so a member who cannot use it gets 404.'
      produces 'application/json'

      response '200', 'hidden platforms' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/HiddenPlatforms' } },
          required: %w[data]
      end

      response '403', 'forbidden: caller is not the member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the viewer cannot use the Release Calendar Feature' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    put 'Replace a member\'s Hidden Platforms' do
      tags 'Release Calendar'
      description 'Replaces the member\'s whole set with `platform_ids`: hiding and showing a platform both ' \
                  'send the whole set, and an empty list clears it. An id sent twice counts once. An unknown ' \
                  'platform id, or anything but a list of positive integer ids, returns 422 and changes ' \
                  'nothing; its `error` says why in a sentence the website shows the member. Returns the ' \
                  'whole document, as GET does.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              platform_ids: {
                type: :array, items: { type: :integer },
                description: 'GameDB platform ids to hide. May be empty.',
                example: [ 6, 48 ]
              }
            },
            required: %w[platform_ids]
          }
        },
        required: %w[data]
      }

      response '200', 'saved hidden platforms' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/HiddenPlatforms' } },
          required: %w[data]
      end

      response '422', 'not a list of platform ids, or an unknown platform' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing `data` parameter' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not the member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the viewer cannot use the Release Calendar Feature' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
