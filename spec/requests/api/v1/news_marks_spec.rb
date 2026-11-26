# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/news_mark', type: :request do
  gate = 'Belongs to the News Hub Feature: a member who cannot use it (Preview: Admins and Superadmins only; ' \
         'Off: nobody) gets 404 `not_found`.'

  path '/api/v1/users/{user_id}/news_mark' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord user id of the member. Must be the signed-in member.'

    get 'Show a member\'s News Mark' do
      tags 'News Hub'
      description 'The News Mark: the moment up to which the member has seen the News Hub\'s News Items. The ' \
                  'News page counts News Items posted after it as new. `news_mark` is null until the website ' \
                  'first sets it. Only the member themself may read it; another member, staff and the bot\'s ' \
                  'service token get 403. ' \
                  "#{gate}"
      produces 'application/json'

      response '200', 'News Mark' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/NewsMark' } },
          required: %w[data]
      end

      response '403', 'forbidden: caller is not the member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the member cannot use the News Hub Feature' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    put 'Move a member\'s News Mark forward' do
      tags 'News Hub'
      description 'Moves the News Mark forward, either to an instant (`news_mark`, the newest News Item the ' \
                  'page showed) or to now (`all_seen: true`, Mark all seen). Give exactly one. The News Mark ' \
                  'never moves backwards: an instant before the stored mark keeps the stored one and still ' \
                  'returns 200 with it. An instant past now is clamped to now. Returns the stored News Mark. ' \
                  'Only the member themself may set it. ' \
                  "#{gate}"
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              news_mark: { type: :string, format: 'date-time', example: '2026-11-24T21:40:00.000Z',
                           description: 'ISO 8601 instant to move the News Mark forward to.' },
              all_seen: { type: :boolean, enum: [ true ], description: 'Mark all seen: move the News Mark to now.' }
            }
          }
        },
        required: %w[data]
      }

      response '200', 'the stored News Mark' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/NewsMark' } },
          required: %w[data]
      end

      response '422', 'neither or both of `news_mark` and `all_seen`, a `news_mark` that is not an ISO 8601 ' \
                      'instant, or an `all_seen` that is not true' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing `data` parameter' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not the member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the member cannot use the News Hub Feature' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
