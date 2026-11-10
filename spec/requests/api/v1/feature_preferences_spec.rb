# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/feature_preferences', type: :request do
  path '/api/v1/users/{user_id}/feature_preferences' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord user id of the member. Must be the signed-in member.'

    get 'Show a member\'s Feature Preferences' do
      tags 'Features'
      description 'The hideable Features the member hid from their own view of the website, the Features ' \
                  'they may hide (with where each shows up), and, for an Admin or Superadmin, the ' \
                  '"show Preview features" setting. Only hidden Features are stored, so everything is ' \
                  'shown by default. Only the member themself may read it; another member, staff and the ' \
                  'bot\'s service token get 403. Preferences only shape the session\'s `shown` values; ' \
                  'they never block an endpoint.'
      produces 'application/json'

      response '200', 'feature preferences' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/FeaturePreferences' } },
          required: %w[data]
      end

      response '403', 'forbidden: caller is not the member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a member\'s Feature Preferences' do
      tags 'Features'
      description 'Hides or shows the named Features and, for an Admin or Superadmin, sets the ' \
                  '"show Preview features" setting. Features not named are left as they were. Hiding a ' \
                  'Core Feature, naming an unknown Feature, or a non-staff member sending ' \
                  '`show_preview_features` returns 422 and changes nothing. Only the member themself may ' \
                  'update it. Returns the whole document, as GET does.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            description: 'At least one of `hidden` and `show_preview_features`.',
            properties: {
              hidden: {
                type: :object,
                description: 'Feature key to true (hide it) or false (show it again).',
                additionalProperties: { type: :boolean },
                example: { journals: true, reviews: false }
              },
              show_preview_features: {
                type: :boolean,
                description: 'Admins and Superadmins only: show Preview Features on the website.'
              }
            }
          }
        },
        required: %w[data]
      }

      response '200', 'updated feature preferences' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/FeaturePreferences' } },
          required: %w[data]
      end

      response '422', 'Core Feature, unknown Feature, bad value, or show_preview_features from a non-staff member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing `data` parameter' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not the member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
