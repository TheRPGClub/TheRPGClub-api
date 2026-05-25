# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/now_playing', type: :request do
  path '/api/v1/users/{user_id}/now_playing' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'List a user\'s now-playing games' do
      tags 'Now Playing'
      description 'Returns the games a specific user is currently playing, newest first.'
      produces 'application/json'
      parameter name: :limit, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :offset, in: :query, schema: { type: :integer, default: 0 }, required: false
      parameter name: :page, in: :query, schema: { type: :integer, default: 1 }, required: false

      response '200', 'now-playing list' do
        schema type: :object, properties: {
          data: { type: :array, items: { type: :object, additionalProperties: true } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
