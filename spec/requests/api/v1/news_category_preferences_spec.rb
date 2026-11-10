# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/news_category_preferences', type: :request do
  gate = 'Belongs to the News Hub Feature: a member who cannot use it (Preview: Admins and Superadmins only; ' \
         'Off: nobody) gets 404 `not_found`.'

  path '/api/v1/users/{user_id}/news_category_preferences' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord user id of the member. Must be the signed-in member.'

    get 'Show a member\'s News Category Preferences' do
      tags 'News Hub'
      description 'The News Categories the member switched off, which `GET /api/v1/news_items` leaves out of ' \
                  'its default view (no `category`), and every News Category in order with its switch. Only ' \
                  'switched-off categories are stored, so every News Category is on by default. Only the member ' \
                  'themself may read it; another member, staff and the bot\'s service token get 403. A ' \
                  'preference never blocks a request and has no effect in Discord. ' \
                  "#{gate}"
      produces 'application/json'

      response '200', 'News Category Preferences' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/NewsCategoryPreferences' } },
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

    patch 'Update a member\'s News Category Preferences' do
      tags 'News Hub'
      description 'Switches the named News Categories off (true) or on again (false). News Categories not ' \
                  'named are left as they were; repeating a change is a no-op. An unknown News Category key ' \
                  'or a value that is not true or false returns 422 and changes nothing. Only the member ' \
                  'themself may update it. Returns the whole document, as GET does. ' \
                  "#{gate}"
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              hidden: {
                type: :object,
                description: 'News Category key to true (switch it off) or false (switch it on again).',
                additionalProperties: { type: :boolean },
                example: { rumours: true, industry: false }
              }
            },
            required: %w[hidden]
          }
        },
        required: %w[data]
      }

      response '200', 'updated News Category Preferences' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/NewsCategoryPreferences' } },
          required: %w[data]
      end

      response '422', 'missing `hidden`, an unknown News Category key, or a value that is not true or false' do
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
