# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/public_reminders', type: :request do
  # The client-writable RpgClubPublicReminder columns. `reminder_id` and the
  # timestamps are server-managed.
  writable = {
    channel_id: { type: :string, description: 'Channel to post the reminder in. Required on create.' },
    message: { type: :string, description: 'Reminder text. Required on create.' },
    due_at: { type: :string, format: 'date-time', description: 'When the reminder is due. Required on create.' },
    recur_every: { type: :integer, nullable: true, description: 'Optional recurrence interval (paired with `recur_unit`).' },
    recur_unit: { type: :string, nullable: true, description: 'Optional recurrence unit (e.g. "days").' },
    enabled: { type: :boolean, description: 'Whether the reminder is active. Optional; defaults to true.' },
    created_by: { type: :string, nullable: true, description: 'Optional Discord id of the creator.' }
  }

  path '/api/v1/public_reminders' do
    get 'List public reminders' do
      tags 'Public Reminders'
      description 'Returns reminders the bot will post to the public channel. Pass `enabled=true|false` ' \
                  'to filter. Open to any authenticated caller.'
      produces 'application/json'
      parameter name: :enabled, in: :query, schema: { type: :boolean }, required: false
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'public reminders' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/PublicReminder' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a public reminder' do
      tags 'Public Reminders'
      description 'Open to any authenticated caller. `channel_id`, `message` and `due_at` are required; ' \
                  '`recur_every`/`recur_unit` (recurrence), `enabled` (defaults true) and `created_by` ' \
                  'are optional.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[channel_id message due_at] } },
        required: %w[data]
      }

      response '201', 'reminder created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/PublicReminder' } }
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/public_reminders/due' do
    get 'List due public reminders' do
      tags 'Public Reminders'
      description 'Service-only poll endpoint. Returns enabled reminders whose `due_at` has passed ' \
                  '(`<= now`), ordered by `due_at` ascending. Unpaginated — every due reminder is ' \
                  'returned so the bot can fire them all in one poll cycle.'
      produces 'application/json'

      response '200', 'due reminders' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/PublicReminder' } }
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

  path '/api/v1/public_reminders/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubPublicReminder id.'

    get 'Show a public reminder' do
      tags 'Public Reminders'
      produces 'application/json'

      response '200', 'reminder detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/PublicReminder' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a public reminder' do
      tags 'Public Reminders'
      description 'Partial update: send any subset of the writable columns.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/PublicReminder' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    put 'Replace a public reminder (alias)' do
      tags 'Public Reminders'
      description 'Alias for PATCH (applied as a partial assign).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/PublicReminder' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a public reminder' do
      tags 'Public Reminders'
      produces 'application/json'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedResponse'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
