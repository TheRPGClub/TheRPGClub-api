# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/user_channel_counts', type: :request do
  path '/api/v1/users/{user_id}/channel_counts' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'List a user\'s per-channel message counts' do
      tags 'User Channel Counts'
      description 'Read-only breakdown of how many messages the user has sent in each channel, ' \
                  'as maintained by the bot\'s channel-history scan. Ordered by message count ' \
                  'descending. The bot owns all writes.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'channel message counts' do
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
