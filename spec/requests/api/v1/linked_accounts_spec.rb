# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/linked_accounts', type: :request do
  owner_only = 'Owner-only: the member themselves, or the bot service token. Admins are refused.'
  account_ref = { '$ref' => '#/components/schemas/LinkedAccount' }
  account_body = { type: :object, properties: { data: account_ref }, required: %w[data] }

  path '/api/v1/users/{user_id}/linked_accounts' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get "List a member's Linked Accounts" do
      tags 'Linked Accounts'
      description "#{owner_only} At most one per Provider, ordered by Provider; not paginated."
      produces 'application/json'

      response '200', 'Linked Accounts' do
        schema type: :object, properties: { data: { type: :array, items: account_ref } }, required: %w[data]
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Link a Provider account' do
      tags 'Linked Accounts'
      description "#{owner_only} Resolves `identifier` through the Provider and stores its stable id " \
                  '(RA ULID, SteamID64 or PSN accountId) with `sync_status: pending` and `sync_mode: backfill`, ' \
                  "due now, then starts the Provider's sync. Linking is trust-based: ownership is not verified."
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              provider: { type: :string, enum: UserLinkedAccount::PROVIDERS },
              identifier: {
                type: :string,
                description: 'retroachievements: username. steam: vanity name, steamcommunity.com profile URL ' \
                             '(/id/ or /profiles/) or SteamID64. psn: online ID.'
              }
            },
            required: %w[provider identifier]
          }
        },
        required: %w[data]
      }

      response '201', 'Linked Account created' do
        schema account_body
      end

      response '400', 'missing data or blank identifier' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'provider_already_linked, identity_claimed, not_found, private or invalid_provider' do
        schema '$ref' => '#/components/schemas/LinkedAccountError'
      end

      response '503', 'provider_unavailable: the Provider could not be reached; try again later' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/users/{user_id}/linked_accounts/{id}' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true
    parameter name: :id, in: :path, schema: { type: :integer }, required: true, description: 'user_linked_accounts.id.'

    delete 'Unlink a Linked Account' do
      tags 'Linked Accounts'
      description "The owner, the bot service, or an admin (role_admin or dev). Deletes the account's Unlocks " \
                  'and progress for that Provider; the shared Achievement definitions stay.'
      produces 'application/json'

      response '200', 'unlinked' do
        schema '$ref' => '#/components/schemas/DeletedResponse'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: neither the owner nor an admin' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', "no such Linked Account for this member" do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/users/{user_id}/linked_accounts/{id}/retry' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true
    parameter name: :id, in: :path, schema: { type: :integer }, required: true, description: 'user_linked_accounts.id.'

    post 'Retry a stopped Linked Account' do
      tags 'Linked Accounts'
      description "#{owner_only} Only from `private`, `not_found` or `error`: resets to `pending` (clearing " \
                  '`sync_error`), due now, as a Backfill if none has finished yet, otherwise incremental, and ' \
                  "starts the Provider's sync."
      produces 'application/json'

      response '200', 'Retry queued' do
        schema account_body
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no such Linked Account for this member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'retry_not_allowed: the account is ok or pending' do
        schema '$ref' => '#/components/schemas/LinkedAccountError'
      end
    end
  end

  path '/api/v1/users/{user_id}/linked_accounts/{id}/sync' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true
    parameter name: :id, in: :path, schema: { type: :integer }, required: true, description: 'user_linked_accounts.id.'

    post 'Sync now' do
      tags 'Linked Accounts'
      description "#{owner_only} At most once per 15 minutes. Stamps `sync_requested_at` and makes the account " \
                  'due now (incremental, or still a Backfill if none has finished), then starts the ' \
                  "Provider's sync. A `private` or `not_found` account needs Retry instead."
      produces 'application/json'

      response '200', 'sync queued' do
        schema account_body
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no such Linked Account for this member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'retry_required: the account is private or not_found' do
        schema '$ref' => '#/components/schemas/LinkedAccountError'
      end

      response '429', 'sync_cooldown: within 15 minutes of the last Sync now' do
        schema '$ref' => '#/components/schemas/SyncCooldownError'
      end
    end
  end
end
