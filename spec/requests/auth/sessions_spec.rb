# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'auth/sessions', type: :request do
  path '/auth/logout' do
    delete 'Log out' do
      tags 'Auth'
      description 'Revokes the bearer `UserSessionToken` (if present), logs out the warden session, and resets the cookie session. ' \
                  'Authentication is not required — the endpoint is safe to call when already logged out.'
      produces 'application/json'
      security []

      response '200', 'logged out' do
        schema type: :object, properties: { ok: { type: :boolean, example: true } }, required: %w[ok]
      end
    end
  end
end
