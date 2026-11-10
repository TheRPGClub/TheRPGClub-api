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
                         'caller\'s dev/longstanding flags. `admin`, `moderator`, `regular` and ' \
                         '`member` follow the member\'s Discord roles: refreshed at sign-in and ' \
                         'whenever the bot reports a role change. Null for a service principal or an ' \
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
          },
          features: {
            type: :array,
            description: 'The Features this viewer may see, in registry order (Features::Access). ' \
                         'Admins and Superadmins get every Feature in every state; anyone else gets ' \
                         'only Live Features, so a Preview or Off Feature never reaches a member. A ' \
                         'Feature with no stored Feature Flag state reads as Preview.',
            items: {
              type: :object,
              properties: {
                key: { type: :string, example: 'reviews' },
                name: { type: :string, example: 'Reviews' },
                state: { type: :string, enum: %w[off preview live] },
                hideable: { type: :boolean, description: 'False for a Core Feature, which members cannot hide.' },
                shown: { type: :boolean, description: 'Whether the website shows this Feature to the viewer.' },
                preview: {
                  type: :boolean,
                  description: 'True when the viewer sees the Feature only because they are staff (Preview).'
                }
              },
              required: %w[key name state hideable shown preview]
            }
          }
        }, required: %w[principal features]
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
