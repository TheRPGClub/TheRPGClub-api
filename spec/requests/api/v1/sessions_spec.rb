# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/sessions', type: :request do
  path '/api/v1/session' do
    get 'Current session' do
      tags 'Sessions'
      description 'Returns the authenticated principal (Discord user or service account) and, when applicable, RPG Club membership info.'
      produces 'application/json'

      response '200', 'current session' do
        schema type: :object, properties: {
          principal: {
            type: :object,
            description: 'Auth::Principal payload — shape varies between Discord-user and service principals.',
            additionalProperties: true
          },
          membership: {
            type: :object,
            nullable: true,
            description: 'RPG Club membership info merged with dev/longstanding role flags.',
            additionalProperties: true
          }
        }, required: %w[principal]
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
