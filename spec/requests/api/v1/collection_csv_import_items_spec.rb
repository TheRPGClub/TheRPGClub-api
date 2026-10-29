# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/collection_csv_import_items', type: :request do
  # The client-writable RpgClubCollectionCsvImportItem columns for the match /
  # outcome the bot's matcher records after processing a row. `import_id`,
  # `row_index` and the `raw_*` fields are set at create time and not editable
  # here.
  update_writable = {
    status: { type: :string, enum: %w[pending added updated skipped failed], description: 'New item status.' },
    platform_id: { type: :integer, nullable: true },
    ownership_type: { type: :string, nullable: true },
    note: { type: :string, nullable: true },
    match_confidence: { type: :string, nullable: true },
    match_candidate_json: { type: :string, nullable: true, description: 'JSON-encoded match candidate, stored and returned verbatim.' },
    gamedb_game_id: { type: :integer, nullable: true },
    collection_entry_id: { type: :integer, nullable: true, description: 'The UserGameCollection entry created for this row.' },
    result_reason: { type: :string, nullable: true },
    error_text: { type: :string, nullable: true }
  }

  path '/api/v1/collection_csv_import_items/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCollectionCsvImportItem item_id.'

    get 'Show a collection CSV import item' do
      tags 'Collection CSV Imports'
      description 'Owner-only (resolved through the parent import).'
      produces 'application/json'

      response '200', 'import item' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CollectionCsvImportItem' } }
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

    patch 'Update a collection CSV import item' do
      tags 'Collection CSV Imports'
      description 'Service (bot) only. Records the match/outcome after the bot processes this row. ' \
                  'Rolled back instead of persisted if the item\'s import is in test_mode.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: update_writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CollectionCsvImportItem' } }
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

  path '/api/v1/collection_csv_import_items/{id}/apply' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCollectionCsvImportItem item_id.'

    post 'Apply a chosen game to a collection CSV import row' do
      tags 'Collection CSV Imports'
      description 'Owner-only (#290). Send exactly one of `game_id` (a GameDB game) or `igdb_id` (imported into ' \
                  'GameDB first, owner-safe, and stored as the row\'s only candidate). Adds the game to the ' \
                  'owner\'s collection with the row\'s platform, ownership and note, and sets the row to ' \
                  '`added`/`manual_remap` (`platform_unresolved` when the platform no longer resolves), or ' \
                  '`skipped`/`duplicate` when the entry already exists, or `failed`/`add_failed`. Returns the ' \
                  'updated item. Rolled back instead of persisted if the import is in test_mode.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: {
          game_id: { type: :integer, description: 'GameDB game_id to apply.' },
          igdb_id: { type: :integer, description: 'IGDB id to import and apply.' }
        } } },
        required: %w[data]
      }

      response '200', 'updated item' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CollectionCsvImportItem' } }
      end

      response '403', 'forbidden — caller is not the owner or service' do
        schema '$ref' => '#/components/schemas/Error'
      end
      response '404', 'item not found, `game_not_found`, or `igdb_game_not_found`' do
        schema '$ref' => '#/components/schemas/Error'
      end
      response '409', '`import_not_active` (the import is not active) or `item_not_pending` (the row was already resolved)' do
        schema '$ref' => '#/components/schemas/Error'
      end
      response '422', '`game_id_or_igdb_id_required`, `invalid_igdb_id` or `igdb_not_configured`' do
        schema '$ref' => '#/components/schemas/Error'
      end
      response '502', '`igdb_request_failed`' do
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

  path '/api/v1/collection_csv_import_items/{id}/skip' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCollectionCsvImportItem item_id.'

    post 'Skip a collection CSV import row' do
      tags 'Collection CSV Imports'
      description 'Owner-only (#290). Sets the row to `skipped`/`manual_skip`. Returns the updated item. ' \
                  'Rolled back instead of persisted if the import is in test_mode.'
      produces 'application/json'

      response '200', 'updated item' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CollectionCsvImportItem' } }
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
      response '409', '`import_not_active` (the import is not active) or `item_not_pending` (the row was already resolved)' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/collection_csv_import_items/{id}/remap' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCollectionCsvImportItem item_id.'

    post 'Search GameDB for a different title for a collection CSV import row' do
      tags 'Collection CSV Imports'
      description 'Owner-only (#290). Re-searches GameDB with `title` and stores the candidates and confidence ' \
                  'on the row (`result_reason` `no_candidate` when there are none). Returns the same review ' \
                  'payload as `advance`. A single candidate that exactly matches the row\'s original title is ' \
                  'auto-applied by the next `advance`. Rolled back instead of persisted if the import is in ' \
                  'test_mode.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: { title: { type: :string } }, required: %w[title] } },
        required: %w[data]
      }

      response '200', 'review payload' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CollectionCsvImportReview' } }
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
      response '409', '`import_not_active` (the import is not active) or `item_not_pending` (the row was already resolved)' do
        schema '$ref' => '#/components/schemas/Error'
      end
      response '422', '`title_required`' do
        schema '$ref' => '#/components/schemas/Error'
      end
      response '400', 'missing `data` parameter' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/collection_csv_import_items/{id}/igdb_candidates' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCollectionCsvImportItem item_id.'

    get 'IGDB suggestions for a collection CSV import row' do
      tags 'Collection CSV Imports'
      description 'Owner-only (#290). Searches IGDB for `q`, or else the row\'s title, trying progressive ' \
                  'title variants until one has hits (at most 10). Each hit carries `already_imported`. ' \
                  'Apply one with `apply {igdb_id}`.'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: false,
                description: 'Title to search instead of the row\'s raw_title.'

      response '200', 'IGDB candidates' do
        schema type: :object, properties: { data: { type: :array, items: { '$ref' => '#/components/schemas/ImportIgdbCandidate' } } }
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
      response '422', '`igdb_not_configured`' do
        schema '$ref' => '#/components/schemas/Error'
      end
      response '502', '`igdb_request_failed`' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
