# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/collection_csv_imports', type: :request do
  # The client-writable RpgClubCollectionCsvImportItem fields accepted inside
  # `items` on create. `import_id`/`status` are server-managed.
  create_item_writable = {
    row_index: { type: :integer, description: 'Position of this row in the source CSV. Defaults to the array index.' },
    raw_title: { type: :string, nullable: true },
    raw_platform: { type: :string, nullable: true },
    raw_ownership_type: { type: :string, nullable: true },
    raw_note: { type: :string, nullable: true },
    raw_gamedb_id: { type: :integer, nullable: true },
    raw_igdb_id: { type: :integer, nullable: true }
  }
  create_writable = {
    source_file_name: { type: :string, nullable: true },
    source_file_size: { type: :integer, nullable: true },
    template_version: { type: :string, nullable: true },
    items: { type: :array, items: { type: :object, properties: create_item_writable },
             description: 'The parsed CSV rows to import, in order.' },
    test_mode: { type: :boolean, default: false,
                 description: 'Dry-run session (#187): the session row itself is persisted, but every ' \
                             'subsequent write scoped to it (item inserts/updates, status/current_index ' \
                             'updates) is rolled back instead of committed.' }
  }
  update_writable = {
    status: { type: :string, enum: %w[active paused completed canceled], description: 'New status for the import job.' },
    current_index: { type: :integer, description: 'Row index the bot has resumed processing through.' }
  }

  path '/api/v1/users/{user_id}/collection_csv_imports' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCollectionCsvImport owner user_id.'

    post 'Start a collection CSV import job' do
      tags 'Collection CSV Imports'
      description 'Owner-only (the bot service token counts as owner). Creates the import job ' \
                  'and inserts all row items — given as `items` — in one call. `test_mode: true` ' \
                  'marks this a dry-run session — the session row itself is always persisted, but ' \
                  'all subsequent writes scoped to it are rolled back.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: create_writable } },
        required: %w[data]
      }

      response '201', 'import job created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CollectionCsvImport' } }
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

  path '/api/v1/users/{user_id}/collection_csv_imports/active' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCollectionCsvImport owner user_id.'

    get "Get the user's active or paused import" do
      tags 'Collection CSV Imports'
      description 'Owner-only. Returns the user\'s active or paused import, if any, for resuming ' \
                  'after a bot restart, or 404 if none exists.'
      produces 'application/json'

      response '200', 'active import' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CollectionCsvImport' } }
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

  path '/api/v1/collection_csv_imports/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCollectionCsvImport import_id.'

    get 'Show a collection CSV import job' do
      tags 'Collection CSV Imports'
      description 'Owner-only.'
      produces 'application/json'

      response '200', 'import job' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CollectionCsvImport' } }
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

    patch 'Update a collection CSV import job' do
      tags 'Collection CSV Imports'
      description 'Owner-only. Partial update — typically the status transition and resume ' \
                  'checkpoint (`current_index`) as the bot works through the items. Rolled back ' \
                  'instead of persisted if the import is in test_mode.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: update_writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CollectionCsvImport' } }
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

  path '/api/v1/collection_csv_imports/{id}/summary' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCollectionCsvImport import_id.'

    get 'Summarize a collection CSV import job' do
      tags 'Collection CSV Imports'
      description 'Owner-only. Item counts grouped by status and by result_reason, replacing the ' \
                  "bot's countItemsByStatus/countItemsByReason."
      produces 'application/json'

      response '200', 'summary' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CollectionCsvImportSummary' } }
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

  path '/api/v1/collection_csv_imports/{id}/items/next_pending' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCollectionCsvImport import_id.'

    get 'Get the next pending import item' do
      tags 'Collection CSV Imports'
      description 'Owner-only. Returns the next pending item ordered by row_index, or `data: null` ' \
                  'once every row has been processed.'
      produces 'application/json'

      response '200', 'next pending item, or null' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CollectionCsvImportItem' } }
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
end
