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
            description: 'The authenticated principal (Auth::Principal#as_json). `kind` is ' \
                         '"discord_user" or "service"; the name/avatar fields are null for a ' \
                         'service principal.',
            properties: {
              kind: { type: :string, example: 'discord_user' },
              id: { type: :string },
              discord_id: { type: :string, nullable: true },
              username: { type: :string, nullable: true },
              global_name: { type: :string, nullable: true },
              avatar: { type: :string, nullable: true },
              service: { type: :boolean },
              dev: { type: :boolean },
              longstanding: { type: :boolean }
            },
            required: %w[kind id service dev longstanding]
          },
          membership: {
            type: :object,
            nullable: true,
            description: 'RPG Club membership flags (RpgClubUser#membership) merged with the ' \
                         'caller\'s dev/longstanding flags. Null for a service principal or an ' \
                         'unknown user.',
            properties: {
              admin: { type: :boolean },
              moderator: { type: :boolean },
              regular: { type: :boolean },
              member: { type: :boolean },
              newcomer: { type: :boolean },
              active: { type: :boolean },
              dev: { type: :boolean },
              longstanding: { type: :boolean }
            }
          }
        }, required: %w[principal]
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
