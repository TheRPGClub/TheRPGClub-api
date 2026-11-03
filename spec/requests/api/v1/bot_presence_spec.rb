# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/bot_presence', type: :request do
  # The client-writable BotPresenceHistory columns. The surrogate `id` and the
  # DB-stamped `set_at` are server-managed and stripped from writes.
  writable = {
    activity_name: { type: :string, description: 'The presence activity text. Required on create.' },
    set_by_user_id: { type: :string, nullable: true,
                      description: 'Discord user id that set the presence. Service only; a staff ' \
                                   'caller is recorded from the session and this is ignored.' },
    set_by_username: { type: :string, nullable: true,
                       description: 'Discord username that set the presence. Service only; a staff ' \
                                    'caller is recorded from the session and this is ignored.' }
  }

  path '/api/v1/bot_presence' do
    get 'List bot presence history' do
      tags 'Bot Presence'
      description 'Moderator and up, or the service. Returns presence history, newest first. ' \
                  '`limit` (capped at 50) sizes the page.'
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

      response '403', 'forbidden: caller is not Moderator and up or the service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Save a bot presence entry' do
      tags 'Bot Presence'
      description 'Moderator and up, or the service. Records a new presence entry. `set_at` is ' \
                  'stamped by the server (defaults to now()). On a staff create the setter id and ' \
                  'name come from the session, never the body, and a `presence_set` bot job is ' \
                  'queued so the bot applies the presence at once. The service (the bot itself, ' \
                  'which has already applied it) queues no job.'
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

      response '403', 'forbidden: caller is not Moderator and up or the service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'activity name too long' do
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
      description 'Moderator and up, or the service. Returns the most recent presence entry (the ' \
                  'current presence), or `{ "data": null }` when no entries exist.'
      produces 'application/json'

      response '200', 'latest presence entry (or null)' do
        schema type: :object, properties: {
          data: { allOf: [ { '$ref' => '#/components/schemas/BotPresence' } ], nullable: true }
        }
      end

      response '403', 'forbidden: caller is not Moderator and up or the service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
