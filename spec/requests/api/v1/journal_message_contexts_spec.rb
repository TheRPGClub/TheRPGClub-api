# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/journal_message_contexts', type: :request do
  # All JournalMessageContext columns are client-writable and NOT NULL (no
  # server-generated id — `message_id` is the route key).
  writable = {
    channel_id: { type: :string, description: 'Discord channel id. Required.' },
    message_id: { type: :string, description: 'Discord message id (the record key). Required.' },
    created_at_ms: { type: :integer, description: 'Message creation time as epoch milliseconds. Required.' },
    owner_user_id: { type: :string, description: 'Discord id of the journaling user. Required.' },
    game_id: { type: :integer, description: 'The associated gamedb_games.game_id. Required.' }
  }

  path '/api/v1/journal_message_contexts' do
    get 'List journal message contexts' do
      tags 'Journal Message Contexts'
      description 'Returns Discord messages tagged with game journal context. ' \
                  'Optionally filter by channel_id or game_id. Open to any authenticated caller.'
      produces 'application/json'
      parameter name: :channel_id, in: :query, schema: { type: :string }, required: false
      parameter name: :game_id, in: :query, schema: { type: :integer }, required: false
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'journal message contexts' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/JournalMessageContext' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a journal message context' do
      tags 'Journal Message Contexts'
      description 'Records a Discord message as a journal message context (sent by the bot service ' \
                  'principal). All five fields are required.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: { type: :object, properties: writable, required: %w[channel_id message_id created_at_ms owner_user_id game_id] }
        },
        required: %w[data]
      }

      response '201', 'context created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/JournalMessageContext' } }
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/journal_message_contexts/{message_id}' do
    parameter name: :message_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord message id (snowflake — globally unique, used as the route key).'

    get 'Show a journal message context' do
      tags 'Journal Message Contexts'
      produces 'application/json'

      response '200', 'context detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/JournalMessageContext' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a journal message context' do
      tags 'Journal Message Contexts'
      description 'Partial update: send any subset of the writable columns.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/JournalMessageContext' } }
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

    put 'Replace a journal message context (alias)' do
      tags 'Journal Message Contexts'
      description 'Alias for PATCH (applied as a partial assign).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/JournalMessageContext' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a journal message context' do
      tags 'Journal Message Contexts'
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
