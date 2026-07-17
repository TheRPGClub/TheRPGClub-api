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
      description 'Owner-only. Records the match/outcome after the bot processes this app. Rolled ' \
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
