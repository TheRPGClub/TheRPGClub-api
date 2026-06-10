# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/user_nick_history', type: :request do
  path '/api/v1/users/{user_id}/nick_history' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'List a user\'s nickname history' do
      tags 'User Nick History'
      description 'Read-only history of the user\'s nickname changes (old/new nick per event), ' \
                  'as recorded by the bot. Ordered newest first. The bot owns all writes.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'nickname history' do
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
