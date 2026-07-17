# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/steam_collection_imports', type: :request do
  create_writable = {
    user_id: { type: :string, description: 'RpgClubSteamCollectionImport owner user_id. Required.' },
    steam_id64: { type: :string, description: "The user's Steam 64-bit id. Required." },
    steam_profile_ref: { type: :string, nullable: true, description: 'Vanity URL or profile ref used to resolve steam_id64.' },
    source_profile_name: { type: :string, nullable: true, description: 'Steam display name at import time.' },
    test_mode: { type: :boolean, default: false,
                 description: 'Dry-run session (#166): the session row itself is persisted, but every ' \
                             'subsequent write scoped to it (item inserts/updates, status/current_index ' \
                             'updates) is rolled back instead of committed.' }
  }
  update_writable = {
    status: { type: :string, enum: %w[active paused completed canceled], description: 'New status for the import job.' },
    current_index: { type: :integer, description: 'App index the bot has resumed processing through.' }
  }

  path '/api/v1/steam_collection_imports' do
    post 'Start a Steam collection import job' do
      tags 'Steam Collection Imports'
      description 'Owner-only (the bot service token counts as owner; owner_id is taken from `user_id` in ' \
                  'the body). Creates the import job; apps are bulk-inserted separately via ' \
                  '`POST /steam_collection_imports/{id}/items`.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: create_writable, required: %w[user_id steam_id64] } },
        required: %w[data]
      }

      response '201', 'import job created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SteamCollectionImport' } }
      end

      response '403', 'forbidden — caller is not the owner or service' do
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

  path '/api/v1/users/{user_id}/steam_collection_imports/active' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubSteamCollectionImport owner user_id.'

    get "Get the user's active or paused Steam import" do
      tags 'Steam Collection Imports'
      description 'Owner-only. Returns the user\'s active or paused import, if any, for resuming ' \
                  'after a bot restart, or 404 if none exists.'
      produces 'application/json'

      response '200', 'active import' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SteamCollectionImport' } }
      end

      response '403', 'forbidden — caller is not the owner or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no active or paused import' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/steam_collection_imports/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubSteamCollectionImport import_id.'

    get 'Show a Steam collection import job' do
      tags 'Steam Collection Imports'
      description 'Owner-only.'
      produces 'application/json'

      response '200', 'import job' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SteamCollectionImport' } }
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

    patch 'Update a Steam collection import job' do
      tags 'Steam Collection Imports'
      description 'Owner-only. Partial update — typically the status transition and resume ' \
                  'checkpoint (`current_index`) as the bot works through the apps. Rolled back ' \
                  'instead of persisted if the import is in test_mode.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: update_writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SteamCollectionImport' } }
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
  end
end
