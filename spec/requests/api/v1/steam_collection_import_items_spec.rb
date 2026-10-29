# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/steam_collection_import_items', type: :request do
  # The client-writable RpgClubSteamCollectionImportItem fields accepted
  # inside `items` on the bulk-insert. `import_id`/`status` are server-managed.
  create_item_writable = {
    row_index: { type: :integer, description: "Position of this app in the source list. Defaults to the array index." },
    steam_app_id: { type: :integer, description: 'Steam appid. Required.' },
    steam_app_name: { type: :string, description: 'Steam app display name. Required.' },
    playtime_forever_min: { type: :integer, nullable: true },
    playtime_windows_min: { type: :integer, nullable: true },
    playtime_mac_min: { type: :integer, nullable: true },
    playtime_linux_min: { type: :integer, nullable: true },
    playtime_deck_min: { type: :integer, nullable: true },
    last_played_at: { type: :string, format: 'date-time', nullable: true }
  }
  create_writable = {
    items: { type: :array, items: { type: :object, properties: create_item_writable },
             description: 'The Steam library apps to import, in order.' }
  }
  update_writable = {
    status: { type: :string, enum: %w[pending added updated skipped failed], description: 'New item status.' },
    match_confidence: { type: :string, enum: %w[exact fuzzy manual], nullable: true },
    match_candidate_json: { type: :string, nullable: true, description: 'JSON-encoded match candidate, stored and returned verbatim.' },
    gamedb_game_id: { type: :integer, nullable: true },
    collection_entry_id: { type: :integer, nullable: true, description: 'The UserGameCollection entry created for this app.' },
    result_reason: { type: :string, nullable: true },
    error_text: { type: :string, nullable: true }
  }

  path '/api/v1/steam_collection_imports/{id}/items' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubSteamCollectionImport import_id.'

    post 'Bulk-insert Steam collection import items' do
      tags 'Steam Collection Imports'
      description 'Owner-only. Inserts all apps — given as `items` — as pending items and bumps ' \
                  'the import\'s total_count. Rolled back instead of persisted if the import is in test_mode.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: create_writable } },
        required: %w[data]
      }

      response '201', 'items inserted' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SteamCollectionImport' } }
      end

      response '403', 'forbidden — caller is not the owner or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'import not found' do
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

  path '/api/v1/steam_collection_imports/{id}/items/next_pending' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubSteamCollectionImport import_id.'

    get 'Get the next pending import item' do
      tags 'Steam Collection Imports'
      description 'Owner-only. Returns the next pending item ordered by row_index, or `data: null` ' \
                  'once every app has been processed.'
      produces 'application/json'

      response '200', 'next pending item, or null' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SteamCollectionImportItem' } }
      end

      response '403', 'forbidden — caller is not the owner or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'import not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/steam_collection_imports/{id}/items/counts' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubSteamCollectionImport import_id.'

    get 'Count Steam collection import items by status and result_reason' do
      tags 'Steam Collection Imports'
      description 'Owner-only. Item counts grouped by status and by result_reason, replacing the ' \
                  "bot's countItemsByStatus/countItemsByReason."
      produces 'application/json'

      response '200', 'counts' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SteamCollectionImportCounts' } }
      end

      response '403', 'forbidden — caller is not the owner or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'import not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/steam_collection_import_items/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubSteamCollectionImportItem item_id.'

    get 'Show a Steam collection import item' do
      tags 'Steam Collection Imports'
      description 'Owner-only (resolved through the parent import).'
      produces 'application/json'

      response '200', 'import item' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SteamCollectionImportItem' } }
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

    patch 'Update a Steam collection import item' do
      tags 'Steam Collection Imports'
      description 'Service (bot) only. Records the match/outcome after the bot processes this app. Rolled ' \
                  "back instead of persisted if the item's import is in test_mode."
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: update_writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SteamCollectionImportItem' } }
      end

      response '403', 'forbidden — caller is not the service principal' do
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

  path '/api/v1/steam_collection_import_items/{id}/apply' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubSteamCollectionImportItem item_id.'

    post 'Apply a GameDB or IGDB game to a Steam import item' do
      tags 'Steam Collection Imports'
      description 'Owner-only (#289). Pass `game_id` (a GameDB game) or `igdb_id` (resolved to a GameDB ' \
                  'game, imported from IGDB when needed, without the admin-only `POST /games`). Adds the ' \
                  'game to the owner\'s collection (Digital, Steam platform), maps the Steam app to it, and ' \
                  'returns the item: `added`/`manual_remap` (`platform_unresolved` without a Steam platform), ' \
                  '`skipped`/`duplicate` when already collected, or `failed`/`add_failed`. Errors: ' \
                  '`game_not_found` and `igdb_game_not_found` 404, `invalid_igdb_id` and `igdb_not_configured` ' \
                  '422, `igdb_request_failed` 502. Only for a pending item of an active import: otherwise 422 `item_not_pending` / `import_not_active`. Rolled back in test_mode.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              game_id: { type: :integer, description: 'GameDB game_id. Takes precedence over igdb_id.' },
              igdb_id: { type: :integer, description: 'IGDB game id, imported into GameDB if needed.' }
            }
          }
        },
        required: %w[data]
      }

      response '200', 'the updated item' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SteamCollectionImportItem' } }
      end

      response '400', 'missing `data`, or neither game_id nor igdb_id' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden — caller is not the owner or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'item, GameDB game or IGDB game not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'item not pending, import not active, or IGDB unusable' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '502', 'IGDB request failed (`igdb_request_failed`)' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/steam_collection_import_items/{id}/skip' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubSteamCollectionImportItem item_id.'

    post 'Skip a Steam import item' do
      tags 'Steam Collection Imports'
      description 'Owner-only (#289). Marks the item `skipped`/`manual_skip` and records the Steam app as ' \
                  '`skipped` in the shared app map, so later imports flag it `skip_mapped`. Only for a pending item of an active import: otherwise 422 `item_not_pending` / `import_not_active`. Rolled back in test_mode.'
      produces 'application/json'

      response '200', 'the updated item' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SteamCollectionImportItem' } }
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

      response '422', 'item not pending or import not active' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/steam_collection_import_items/{id}/remap' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubSteamCollectionImportItem item_id.'

    post 'Search GameDB for a Steam import item under another title' do
      tags 'Steam Collection Imports'
      description 'Owner-only (#289). Re-searches GameDB for `title` and persists the candidates on the ' \
                  'item (`no_candidate` when nothing matches, `invalid_remap` for a blank title). Nothing is ' \
                  'applied; the next advance may auto-apply a single exact match. Returns the same payload ' \
                  'as advance, with `auto_applied` 0. Only for a pending item of an active import: otherwise 422 `item_not_pending` / `import_not_active`. Rolled back in test_mode.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: { type: :object, properties: { title: { type: :string, description: 'Title to search for.' } } }
        },
        required: %w[data]
      }

      response '200', 'the item with its new candidates' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SteamCollectionImportReview' } },
               required: %w[data]
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

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'item not pending or import not active' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/steam_collection_import_items/{id}/igdb_candidates' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubSteamCollectionImportItem item_id.'
    parameter name: :q, in: :query, schema: { type: :string }, required: false,
              description: 'Title to search. Defaults to the item\'s Steam app name.'

    get 'IGDB suggestions for a Steam import item' do
      tags 'Steam Collection Imports'
      description 'Owner-only (#289): the member-facing counterpart of the admin-only `GET /igdb/search`. ' \
                  'Searches IGDB by progressive title variants (the first variant with hits wins, at most 10) ' \
                  'and flags each hit `already_imported` when a GameDB game has that igdb_id. Pick one with ' \
                  '`POST .../apply {igdb_id}`.'
      produces 'application/json'

      response '200', 'IGDB candidates' do
        schema type: :object, properties: { data: { type: :array, items: { '$ref' => '#/components/schemas/ImportIgdbCandidate' } } },
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

      response '422', 'IGDB is not configured (`igdb_not_configured`)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '502', 'IGDB request failed (`igdb_request_failed`)' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
