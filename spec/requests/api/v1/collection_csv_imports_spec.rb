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
    csv_text: { type: :string,
                description: 'The raw collection CSV file (#290, web). When present it is parsed and validated ' \
                             'server-side and `items`, `source_file_size` and `template_version` are ignored ' \
                             '(they are derived). Columns: title (required), platform, ownership_type ' \
                             '(Digital|Physical|Subscription|Other, default Digital), note (<= 500 chars), ' \
                             'gamedb_id, igdb_id (at most one). Max 2 MB.' },
    source_file_name: { type: :string, nullable: true },
    source_file_size: { type: :integer, nullable: true },
    template_version: { type: :string, nullable: true },
    items: { type: :array, items: { type: :object, properties: create_item_writable },
             description: 'The pre-parsed CSV rows to import, in order (bot path; ignored with `csv_text`).' },
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
                  'and inserts all row items in one call. Send either the raw file as `csv_text` (parsed and ' \
                  'validated server-side; any problem rejects the whole file with 422 `invalid_csv` and a ' \
                  '`errors` list of `{row_index, column, message}`, where row_index is the 1-based CSV record ' \
                  'and 1 is the header) or the pre-parsed rows as `items`. `test_mode: true` ' \
                  'marks this a dry-run session — the session row itself is always persisted, but ' \
                  'all subsequent writes scoped to it are rolled back.' \
                  ' A user may have only one active or paused import of this kind: starting another ' \
                  'returns 422 `user already has an active or paused import`.'
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

      response '422', 'validation failed: `invalid_csv` (InvalidCsvError) for a bad `csv_text`, otherwise Error' do
        schema oneOf: [ { '$ref' => '#/components/schemas/InvalidCsvError' }, { '$ref' => '#/components/schemas/Error' } ]
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

  path '/api/v1/collection_csv_imports/{id}/advance' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCollectionCsvImport import_id.'

    post 'Advance a collection CSV import to the next row needing review' do
      tags 'Collection CSV Imports'
      description 'Owner-only (#290). Runs the import loop server-side over pending rows in row_index order: ' \
                  'a row with `gamedb_id` is applied (`csv_gamedb_id`; `invalid_row` if the game is unknown), ' \
                  'a row with `igdb_id` is imported from IGDB and applied (`csv_igdb_id`; `invalid_row` on ' \
                  'failure), and a row whose title search yields a single exact candidate is applied ' \
                  '(`auto_match`). Applying uses the row\'s platform (`platform_unresolved` when it no longer ' \
                  'resolves; added without a platform), ownership and note; an entry already in the ' \
                  'collection marks the row `skipped`/`duplicate`. Returns the first row that needs a human ' \
                  'with its stored candidates. `item` is null when nothing is pending (the import is then ' \
                  '`completed`) or when 25 rows were resolved in this call (the import stays `active`: call ' \
                  'again). Rolled back instead of persisted if the import is in test_mode.'
      produces 'application/json'

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
      response '409', '`import_not_active` — the import is paused, completed or canceled' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
