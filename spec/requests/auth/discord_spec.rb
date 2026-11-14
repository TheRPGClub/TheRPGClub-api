# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'auth/discord', type: :request do
  path '/auth/discord' do
    get 'Start Discord OAuth login' do
      tags 'Auth'
      description 'Begins the Discord OAuth flow. The endpoint stores a CSRF `state` value, and the optional `return_to`, ' \
                  'in the session and redirects the browser to Discord\'s authorization URL. Public — does not require authentication.'
      produces 'application/json'
      security []
      parameter name: :return_to, in: :query, schema: { type: :string }, required: false,
                description: 'Website path to come back to after sign-in. Accepted only as a same-origin path: a single ' \
                             'leading slash, no scheme or host, no backslash, no control characters (tabs, newlines), ' \
                             'and at most 1 KB as stored in the session (JSON-encoded bytes, so multi-byte and escaped ' \
                             'characters count for more than one). Anything else is silently discarded.'

      response '302', 'redirecting to Discord' do
        header 'Location', schema: { type: :string }, description: 'Discord authorization URL with the `state` query parameter set.'
      end

      response '422', 'Discord OAuth not configured, or `DISCORD_OAUTH_SUCCESS_REDIRECT` is not an absolute URL' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/auth/discord/callback' do
    get 'Discord OAuth callback' do
      tags 'Auth'
      description 'Exchanges the OAuth `code` for tokens, verifies guild membership and roles, upserts the RPG Club user record, ' \
                  'issues a `UserSessionToken`, and redirects to the configured success URL (the website\'s sign-in callback) ' \
                  'with the token and the `return_to` from the start in the query string. A Discord user who is not in the ' \
                  'club\'s Discord server gets no token and is redirected to the website\'s `/join` page with the `return_to`. ' \
                  'An invalid or missing state, or a failed Discord exchange, redirects to the website\'s front page with ' \
                  '`?error=auth_failed`. Website URLs use the origin of the success URL. A missing `code` (for example, ' \
                  'consent denied on Discord) also redirects to `/?error=auth_failed`. Public — does not require authentication.'
      produces 'application/json'
      security []
      parameter name: :code, in: :query, schema: { type: :string }, required: false,
                description: 'OAuth authorization code from Discord. Absent when the Visitor declined consent.'
      parameter name: :state, in: :query, schema: { type: :string }, required: true, description: 'CSRF state value matching the one set at /auth/discord.'

      response '302', 'redirecting to the success URL with `?token=…&return_to=…`, to `/join?return_to=…` for a non-member, ' \
                      'or to `/?error=auth_failed` when sign-in failed' do
        header 'Location', schema: { type: :string }
      end

      response '422', 'Discord OAuth not configured, or `DISCORD_OAUTH_SUCCESS_REDIRECT` is not an absolute URL' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
