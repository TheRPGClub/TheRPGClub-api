# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/journal_message_contexts', type: :request do
  # All JournalMessageContext columns are client-writable and NOT NULL (no
  # server-generated id — (channel_id, message_id) is the composite key).
  writable = {
    channel_id: { type: :string, description: 'Discord channel id (part of the composite key). Required.' },
    message_id: { type: :string, description: 'Discord message id (part of the composite key). Required.' },
    created_at_ms: { type: :integer, description: 'Message creation time as epoch milliseconds. Required.' },
    owner_user_id: { type: :string, description: 'Discord id of the journaling user. Required.' },
    game_id: { type: :integer, description: 'The associated gamedb_games.game_id. Required.' }
  }

  path '/api/v1/journal_message_contexts' do
    get 'List journal message contexts' do
      tags 'Journal Message Contexts'
      description 'Returns Discord messages tagged with game journal context. ' \
                  'Optionally filter by channel_id, game_id, or created_after_ms (for the active list). ' \
                  'Open to any authenticated caller.'
      produces 'application/json'
      parameter name: :channel_id, in: :query, schema: { type: :string }, required: false
      parameter name: :game_id, in: :query, schema: { type: :integer }, required: false
      parameter name: :created_after_ms, in: :query, schema: { type: :integer },
        required: false, description: 'Only return contexts created at or after this epoch-ms timestamp.'
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

    post 'Upsert a journal message context' do
      tags 'Journal Message Contexts'
      description 'Inserts or updates a journal message context keyed on (channel_id, message_id) ' \
                  '(sent by the bot service principal). All five fields are required. ' \
                  'Returns 201 on insert, 200 on update.'
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

      response '200', 'context updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/JournalMessageContext' } }
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Prune journal message contexts' do
      tags 'Journal Message Contexts'
      description 'Service-only maintenance route: bulk-deletes every context created before the given ' \
                  'cutoff, replacing the bot manual pruning call. `before_ms` is required.'
      produces 'application/json'
      parameter name: :before_ms, in: :query, schema: { type: :integer }, required: true,
        description: 'Delete contexts with created_at_ms strictly before this epoch-ms cutoff.'

      response '200', 'pruned' do
        schema type: :object, properties: { deleted: { type: :boolean }, count: { type: :integer } }
      end

      response '400', 'missing before_ms' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden (not the service principal)' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/journal_message_contexts/{channel_id}/{message_id}' do
    parameter name: :channel_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord channel id (part of the composite key).'
    parameter name: :message_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord message id (part of the composite key).'

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
