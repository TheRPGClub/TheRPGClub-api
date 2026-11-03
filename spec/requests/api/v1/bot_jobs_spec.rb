# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/bot_jobs', type: :request do
  path '/api/v1/bot_jobs' do
    get 'List bot jobs (activity list)' do
      tags 'Bot Jobs'
      description 'Moderators and up, and the service. Newest first. Admins, Superadmins and the service see ' \
                  'every job; Moderators see only the jobs they requested. Members, Regulars and other ' \
                  'non-staff are refused. Each job has its plain summary, status, requester, timestamps and ' \
                  "the bot's error or result text; the payload is never included."
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'bot jobs' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/BotJob' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }, required: %w[data meta]
      end

      response '401', 'not signed in' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not staff (Moderator and up)' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/bot_jobs/claim' do
    post 'Poll for and claim bot jobs' do
      tags 'Bot Jobs'
      description 'Service only. Poll about every 10 seconds. While no work is waiting the API answers an ' \
                  'empty list from a machine-local signal without touching Postgres. Otherwise it claims up to ' \
                  '`limit` queued jobs, oldest first. Act on each one in Discord, then ack it done or failed. ' \
                  'A claim not acked by its `lease_expires_at` goes back to the queue, and fails after ' \
                  "#{BotJob::MAX_ATTEMPTS} claims, so delivery is at-least-once. The lease is five minutes " \
                  'unless the kind has a longer one (long jobs such as a whole-guild scan).'
      produces 'application/json'
      parameter name: :limit, in: :query, schema: { type: :integer, default: 10, minimum: 1, maximum: 50 },
        required: false

      response '200', 'claimed jobs (empty when nothing is waiting)' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/BotJobClaim' } }
        }, required: %w[data]
      end

      response '403', 'not the service' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/bot_jobs/{id}/done' do
    parameter name: :id, in: :path, type: :integer

    post 'Acknowledge a bot job done' do
      tags 'Bot Jobs'
      description 'Service only. Records the job done, with an optional result text the website shows ' \
                  '(e.g. counts). Idempotent: a repeat keeps the first result. A late ack of a job whose ' \
                  'claim timed out still counts.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: false, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: { result_text: { type: :string, nullable: true, maxLength: BotJob::TEXT_MAX } }
          }
        }
      }

      response '200', 'job done' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/BotJob' } }, required: %w[data]
      end

      response '403', 'not the service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'the job already failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'result text too long' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/bot_jobs/{id}/failed' do
    parameter name: :id, in: :path, type: :integer

    post 'Acknowledge a bot job failed' do
      tags 'Bot Jobs'
      description "Service only. Records the job failed with the bot's error message; idempotent. Failed is " \
                  'final: the job is not retried.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: { error_message: { type: :string, minLength: 1, maxLength: 2000 } },
            required: %w[error_message]
          }
        },
        required: %w[data]
      }

      response '200', 'job failed' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/BotJob' } }, required: %w[data]
      end

      response '400', 'missing error message' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not the service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'the job is already done' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/bot_jobs/{id}' do
    parameter name: :id, in: :path, type: :integer

    get "Read a bot job's status" do
      tags 'Bot Jobs'
      description 'The member who queued the job, Admins, Superadmins and the service. Shows its summary ' \
                  "and whether the Discord action is queued, claimed, done (with the bot's result text) or " \
                  "failed (with the bot's error). The payload is not included."
      produces 'application/json'

      response '200', 'job status' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/BotJob' } }, required: %w[data]
      end

      response '401', 'not signed in' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not the requesting member or staff' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
