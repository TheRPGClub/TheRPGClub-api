# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/reminders', type: :request do
  # The client-writable UserReminder columns. `user_id` is taken from the path
  # (never the body); `reminder_id`/timestamps are server-managed; and the bot
  # delivery columns (`sent_at`, `failure_count`, `failed_at`) are read-only —
  # stripped by the controller's #writable_data, so they are returned in the
  # response but never accepted in writes.
  writable = {
    remind_at: { type: :string, format: 'date-time', description: 'When to fire the reminder. Required on create.' },
    content: { type: :string, description: 'The reminder text. Required on create.' },
    is_noisy: { type: :boolean, description: 'Whether the reminder pings noisily. Optional; defaults to false.' }
  }

  path '/api/v1/users/{user_id}/reminders' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'List a user\'s personal reminders' do
      tags 'Reminders'
      description 'The user\'s personal (DM) reminders, ordered by `remind_at`. Distinct from the channel-wide public reminders.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'reminders list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Reminder' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a personal reminder' do
      tags 'Reminders'
      description 'Owner-only. The bot delivery fields (`sent_at`, `failure_count`, `failed_at`) are read-only and ignored if sent.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[remind_at content] } },
        required: %w[data]
      }

      response '201', 'reminder created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Reminder' } }
      end

      response '403', 'forbidden — caller is not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed' do
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

  path '/api/v1/reminders/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'UserReminder reminder_id.'

    get 'Show a personal reminder' do
      tags 'Reminders'
      produces 'application/json'

      response '200', 'reminder detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Reminder' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update (or snooze) a personal reminder' do
      tags 'Reminders'
      description 'Owner-only. Snooze by pushing `remind_at` forward. Bot delivery fields are read-only and ignored if sent.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Reminder' } }
      end

      response '403', 'forbidden — caller is not the owner' do
        schema '$ref' => '#/components/schemas/Error'
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

    put 'Replace a personal reminder (alias)' do
      tags 'Reminders'
      description 'Owner-only. Alias for PATCH (applied as a partial assign).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Reminder' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a personal reminder' do
      tags 'Reminders'
      description 'Owner-only.'
      produces 'application/json'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedResponse'
      end

      response '403', 'forbidden — caller is not the owner' do
        schema '$ref' => '#/components/schemas/Error'
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
