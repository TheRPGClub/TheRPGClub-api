# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/me/theme', type: :request do
  path '/api/v1/me/theme' do
    put 'Choose the signed-in Member\'s Theme' do
      tags 'Member Themes'
      description 'Stores the signed-in Member\'s Theme (docs/adr/0017). `null` returns them to the club ' \
                  'default (monthly-issue), so a later change of default reaches them. Which Themes they may ' \
                  'choose follows the Themes Feature: Off, only the default; Preview, every Theme for staff ' \
                  '(Admin or Superadmin) and only the default for anyone else; Live, every Released Theme for ' \
                  'everyone and every Theme for staff. The default and `null` are always allowed. An unknown ' \
                  'key is 422 and a Theme the Member may not choose 403; neither changes anything. Returns the ' \
                  'session\'s `theme` and `themes` fields. The bot\'s service token gets 403.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          theme: { type: :string, nullable: true, example: 'aero', description: 'A Theme key, or null for the club default.' }
        },
        required: %w[theme]
      }

      response '200', 'the Member\'s Theme, as the session reports it' do
        schema '$ref' => '#/components/schemas/MemberTheme'
      end

      response '422', 'unknown Theme key' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'a Theme the Member may not choose, or the service token' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the signed-in Discord user has no member record' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing `theme` parameter' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
