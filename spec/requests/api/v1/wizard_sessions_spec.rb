# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/wizard_sessions', type: :request do
  # The client-writable RpgClubAdminWizardSession columns. `session_id` is
  # server-generated; `status`/timestamps are server-managed except where noted.
  upsert_writable = {
    command_key: { type: :string, description: 'The wizard command this session belongs to (e.g. nextround-setup). Required.' },
    channel_id: { type: :string, description: 'Discord channel id the wizard is running in. Required.' },
    guild_id: { type: :string, description: 'Discord guild id.', nullable: true },
    state_json: { type: :string, description: 'JSON-encoded wizard state, stored and returned verbatim. Required.' }
  }
  status_writable = {
    status: { type: :string, enum: %w[active completed cancelled], description: 'New status for the session. Required.' }
  }

  path '/api/v1/users/{user_id}/wizard_sessions' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubAdminWizardSession owner_user_id.'

    get 'Get the active wizard session' do
      tags 'Wizard Sessions'
      description 'Owner-only (the bot service token counts as owner). Returns the single ' \
                  'active session for this (command_key, owner, channel), or 404 if none exists.'
      produces 'application/json'
      parameter name: :command_key, in: :query, schema: { type: :string }, required: true
      parameter name: :channel_id, in: :query, schema: { type: :string }, required: true

      response '200', 'active session' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/WizardSession' } }
      end

      response '400', 'missing command_key or channel_id' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden — caller is not the owner or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no active session' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Upsert the active wizard session' do
      tags 'Wizard Sessions'
      description 'Owner-only. Creates or updates the active session for this ' \
                  '(command_key, owner, channel) — called after every wizard step so the bot ' \
                  'can resume after a restart. Reuses the existing session_id when a matching ' \
                  'active session already exists.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: upsert_writable, required: %w[command_key channel_id state_json] } },
        required: %w[data]
      }

      response '200', 'session upserted' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/WizardSession' } }
      end

      response '400', 'missing a required field' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden — caller is not the owner or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete historical wizard sessions' do
      tags 'Wizard Sessions'
      description 'Owner-only. Deletes every non-active session for this (command_key, owner, ' \
                  'channel) — the cleanup step before promoting a session to completed/cancelled. ' \
                  '`command_key`/`channel_id` are required so this can never wipe more than one ' \
                  "wizard's history in one call."
      produces 'application/json'
      parameter name: :command_key, in: :query, schema: { type: :string }, required: true
      parameter name: :channel_id, in: :query, schema: { type: :string }, required: true

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedCountResponse'
      end

      response '400', 'missing command_key or channel_id' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden — caller is not the owner or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/wizard_sessions/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubAdminWizardSession session_id.'

    patch 'Transition a wizard session status' do
      tags 'Wizard Sessions'
      description 'Owner-only. Transitions the session to a new status (e.g. completed, cancelled).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: status_writable, required: %w[status] } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/WizardSession' } }
      end

      response '400', 'missing status' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden — caller is not the owner or service' do
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

    delete 'Delete a wizard session' do
      tags 'Wizard Sessions'
      description 'Owner-only. Removes a single wizard session by session_id.'
      produces 'application/json'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedResponse'
      end

      response '403', 'forbidden — caller is not the owner or service' do
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
