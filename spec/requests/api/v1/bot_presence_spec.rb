# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/bot_presence', type: :request do
  # The client-writable BotPresenceHistory columns. The surrogate `id` and the
  # DB-stamped `set_at` are server-managed and stripped from writes.
  writable = {
    activity_name: { type: :string, description: 'The presence activity text. Required on create.' },
    set_by_user_id: { type: :string, nullable: true, description: 'Discord user id that set the presence. Optional.' },
    set_by_username: { type: :string, nullable: true, description: 'Discord username that set the presence. Optional.' }
  }

  path '/api/v1/bot_presence' do
    get 'List bot presence history' do
      tags 'Bot Presence'
      description 'Service-only. Returns presence history, newest first. `limit` (capped at 50) ' \
                  'sizes the page.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 50 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 50 }, required: false,
        description: 'Max rows to return (capped at 50). Alias for `per`.'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'presence history list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/BotPresence' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '403', 'forbidden — caller is not the service principal' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Save a bot presence entry' do
      tags 'Bot Presence'
      description 'Service-only. Records a new presence entry. `set_at` is stamped by the server ' \
                  '(defaults to now()).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[activity_name] } },
        required: %w[data]
      }

      response '201', 'presence entry created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/BotPresence' } }
      end

      response '403', 'forbidden — caller is not the service principal' do
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

  path '/api/v1/bot_presence/latest' do
    get 'Get the latest bot presence entry' do
      tags 'Bot Presence'
      description 'Service-only. Returns the most recent presence entry, or `{ "data": null }` when ' \
                  'no entries exist.'
      produces 'application/json'

      response '200', 'latest presence entry (or null)' do
        schema type: :object, properties: {
          data: { allOf: [ { '$ref' => '#/components/schemas/BotPresence' } ], nullable: true }
        }
      end

      response '403', 'forbidden — caller is not the service principal' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
