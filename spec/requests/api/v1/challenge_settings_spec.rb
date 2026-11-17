# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/challenge_settings', type: :request do
  path '/api/v1/users/{user_id}/challenge_settings' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord user id of the member.'

    get 'Show a member\'s Challenge settings' do
      tags 'Challenges'
      description 'The member\'s Challenge DM opt-out: whether the bot may DM them Challenge reminders (a ' \
                  'Season ending soon). On until the member turns it off, including for a member the API has ' \
                  'no record of. Only the member, or the bot\'s service token acting for them, may read it.'
      produces 'application/json'

      response '200', 'challenge settings' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/ChallengeSettings' } },
          required: %w[data]
      end

      response '403', 'forbidden: caller is not the member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the Challenges Feature is unavailable to the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Change a member\'s Challenge settings' do
      tags 'Challenges'
      description 'Turns the member\'s Challenge DMs on or off. Only the member, or the bot\'s service token ' \
                  'acting for them, may change it. Creates the member\'s record if the API has none yet. ' \
                  'Returns the whole document, as GET does.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              dms: { type: :boolean, description: 'Whether the member gets Challenge reminder DMs.' }
            },
            required: %w[dms]
          }
        },
        required: %w[data]
      }

      response '200', 'updated challenge settings' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/ChallengeSettings' } },
          required: %w[data]
      end

      response '422', '`dms` missing or not a boolean (error `invalid_settings`)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing `data` parameter' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not the member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the Challenges Feature is unavailable to the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
