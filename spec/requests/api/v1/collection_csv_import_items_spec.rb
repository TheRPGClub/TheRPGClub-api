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
      description 'Owner-only. Records the match/outcome after the bot processes this row. ' \
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
