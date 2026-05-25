# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'auth/discord', type: :request do
  path '/auth/discord' do
    get 'Start Discord OAuth login' do
      tags 'Auth'
      description 'Begins the Discord OAuth flow. The endpoint stores a CSRF `state` value in the session and redirects ' \
                  'the browser to Discord\'s authorization URL. Public — does not require authentication.'
      produces 'application/json'
      security []

      response '302', 'redirecting to Discord' do
        header 'Location', schema: { type: :string }, description: 'Discord authorization URL with the `state` query parameter set.'
      end

      response '422', 'Discord OAuth not configured' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/auth/discord/callback' do
    get 'Discord OAuth callback' do
      tags 'Auth'
      description 'Exchanges the OAuth `code` for tokens, verifies guild membership and roles, upserts the RPG Club user record, ' \
                  'issues a `UserSessionToken`, and redirects to the configured success URL with the token in the query string. ' \
                  'Public — does not require authentication.'
      produces 'application/json'
      security []
      parameter name: :code, in: :query, schema: { type: :string }, required: true, description: 'OAuth authorization code from Discord.'
      parameter name: :state, in: :query, schema: { type: :string }, required: true, description: 'CSRF state value matching the one set at /auth/discord.'

      response '302', 'redirecting to the success URL with `?token=…`' do
        header 'Location', schema: { type: :string }
      end

      response '401', 'invalid OAuth state or token exchange failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'caller is not a member of the RPG Club Discord guild' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'Discord OAuth not configured' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
