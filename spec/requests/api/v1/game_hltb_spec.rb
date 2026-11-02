# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/games/{id}/hltb/lookup', type: :request do
  path '/api/v1/games/{id}/hltb/lookup' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbGame id.'

    post 'Look up HowLongToBeat times' do
      tags 'Games'
      description 'Members role, Moderator, Admin, Superadmin or service. Returns the game\'s saved HLTB ' \
                  'times when it has them (no scrape). Otherwise finds the game\'s HowLongToBeat page ' \
                  'through Google Custom Search ("How long is <title>?") and scrapes it, as the bot\'s ' \
                  '`/hltb` does. A fresh scrape is saved to the HLTB cache only when the game\'s initial ' \
                  'release is more than six months ago (`meta.saved`). Takes no body.'
      produces 'application/json'

      response '200', 'HLTB times' do
        schema '$ref' => '#/components/schemas/HltbLookup'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: Members role or staff required' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'game not found, or `hltb_no_match` when HowLongToBeat has no page for it' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '502', '`hltb_lookup_failed`: Google Custom Search or HowLongToBeat failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '503', '`hltb_not_configured`: Google Custom Search credentials are not set' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
