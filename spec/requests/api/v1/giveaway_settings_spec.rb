# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/giveaway_settings', type: :request do
  path '/api/v1/users/{user_id}/giveaway_settings' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord user id of the donor.'

    get 'Show a user\'s giveaway notification preference' do
      tags 'Game Keys'
      description 'The donor\'s notify-on-claim preference: whether they want to ' \
                  'be notified when one of their donated keys is claimed. ' \
                  'Defaults to `false` for a user with no stored preference.'
      produces 'application/json'

      response '200', 'giveaway settings' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GiveawaySettings' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a user\'s giveaway notification preference' do
      tags 'Game Keys'
      description 'Owner-only: a Discord caller may only update their own ' \
                  'preference; the bot service token may update on anyone\'s ' \
                  'behalf. Creates the user record if it does not yet exist.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              notify_on_claim: { type: :boolean, description: 'Notify the donor when a donated key is claimed.' }
            },
            required: %w[notify_on_claim]
          }
        },
        required: %w[data]
      }

      response '200', 'updated giveaway settings' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GiveawaySettings' } }
      end

      response '403', 'forbidden — caller is not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'missing `notify_on_claim`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing `data` parameter' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
