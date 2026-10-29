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
                  '`POST /steam_collection_imports/{id}/items`.' \
                  ' A user may have only one active or paused import of this kind: starting another ' \
                  'returns 422 `user already has an active or paused import`.'
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

  path '/api/v1/users/{user_id}/steam_collection_imports' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
              description: 'Import owner user_id.'

    post 'Start a Steam collection import from a Steam profile' do
      tags 'Steam Collection Imports'
      description 'Owner-only (#289). Resolves `steam_profile` (a SteamID64, a steamcommunity.com ' \
                  '`profiles/` or `id/` URL, or a vanity name) and fetches the owned library server-side ' \
                  '(needs `STEAM_WEB_API_KEY`), then creates the import and one pending item per app ' \
                  '(`row_index` 1..n). Drive it with `POST /steam_collection_imports/{id}/advance`. ' \
                  'Steam errors: `invalid_identifier` and `private_profile` 422; `api_unavailable` and ' \
                  '`api_unauthorized` 502; `api_rate_limited` and `steam_not_configured` 503. A member may ' \
                  'have only one active or paused import of this kind (422, checked before calling Steam). ' \
                  'In `test_mode` the session is persisted but the items are rolled back.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              steam_profile: { type: :string, example: 'https://steamcommunity.com/id/example',
                               description: 'SteamID64, profile URL or vanity name. Required.' },
              test_mode: { type: :boolean, default: false, description: 'Dry-run session (see TestModeRollback).' }
            },
            required: %w[steam_profile]
          }
        },
        required: %w[data]
      }

      response '201', 'import created with its items' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SteamCollectionImport' } }
      end

      response '400', 'missing `data` parameter' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden — caller is not the owner or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'invalid or private Steam profile, or an import is already open' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '502', 'Steam API failed (`api_unavailable`, `api_unauthorized`)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '503', 'Steam is rate limiting (`api_rate_limited`) or not configured (`steam_not_configured`)' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/steam_collection_imports/{id}/advance' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubSteamCollectionImport import_id.'

    post 'Advance a Steam import to the next item that needs a human' do
      tags 'Steam Collection Imports'
      description 'Owner-only (#289). Pops pending items in `row_index` order and computes their GameDB ' \
                  'candidates (the Steam app map, then a GameDB title search, then the member\'s historically ' \
                  'mapped games), persisting them on the item. A single candidate whose title exactly matches ' \
                  'the Steam name is applied automatically (`auto_match`), up to 25 per request. Returns the ' \
                  'first item that needs a human with its candidates; `item` is null when the import is ' \
                  '`completed`, or when the cap was hit while the import is still `active` (advance again). ' \
                  '409 `import_not_active` unless the import is active. Rolled back in test_mode.'
      produces 'application/json'

      response '200', 'the next item to review, or null' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SteamCollectionImportReview' } },
               required: %w[data]
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden — caller is not the owner or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'import is not active (`import_not_active`)' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
