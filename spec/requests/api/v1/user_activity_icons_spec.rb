# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/user_activity_icons', type: :request do
  path '/api/v1/users/{user_id}/activity_icons' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'List a user\'s activity icons' do
      tags 'User Activity Icons'
      description 'Read-only list of activity icons the bot captured from the user\'s Discord rich ' \
                  'presence (the large/small icons of games and apps they were seen running). ' \
                  'Ordered by most recently seen first. The bot owns all writes.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'activity icons' do
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
