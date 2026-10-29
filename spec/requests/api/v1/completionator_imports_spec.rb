# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/completionator_imports', type: :request do
  # The client-writable RpgClubCompletionatorImportItem fields accepted inside
  # `items` on create. `import_id`/`status` are server-managed.
  create_item_writable = {
    row_index: { type: :integer, description: 'Position of this row in the source export. Defaults to the array index.' },
    game_title: { type: :string, nullable: true },
    platform_name: { type: :string, nullable: true },
    region_name: { type: :string, nullable: true },
    source_type: { type: :string, nullable: true },
    time_text: { type: :string, nullable: true },
    completed_at: { type: :string, format: 'date-time', nullable: true },
    completion_type: { type: :string, nullable: true },
    playtime_hrs: { type: :number, nullable: true }
  }
  create_writable = {
    source_filename: { type: :string, nullable: true },
    csv_text: { type: :string,
                description: 'The raw Completionator export (#291). Parsed server-side (columns name, platform, ' \
                             'region, type, time `Hh:Mm:Ss`, date `M/D/YYYY`; header row skipped). Takes ' \
                             'precedence over `items`.' },
    items: { type: :array, items: { type: :object, properties: create_item_writable },
             description: 'The parsed Completionator export rows to import, in order.' },
    test_mode: { type: :boolean, default: false,
                 description: 'Dry-run session (#188): the session row itself is persisted, but every ' \
                             'subsequent write scoped to it (item inserts/updates, status/current_index ' \
                             'updates) is rolled back instead of committed.' }
  }
  update_writable = {
    status: { type: :string, enum: %w[active paused completed canceled], description: 'New status for the import job.' },
    current_index: { type: :integer, description: 'Row index the bot has resumed processing through.' }
  }

  path '/api/v1/users/{user_id}/completionator_imports' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCompletionatorImport owner user_id.'

    post 'Start a Completionator import job' do
      tags 'Completionator Imports'
      description 'Owner-only (the bot service token counts as owner). Creates the import job ' \
                  'and inserts all row items in one call. Rows come either from `csv_text` (the raw ' \
                  'export, parsed server-side; a malformed or empty export is 422 `invalid_csv`) or ' \
                  'from the pre-parsed `items` (the bot). `invalid_csv` is `{error, errors: [{row_index, column, ' \
                  'message}]}`; every Completionator CSV error is about the whole file, so it is ' \
                  '`row_index: 1, column: "file"`. `test_mode: true` ' \
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
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionatorImport' } }
      end

      response '403', 'forbidden — caller is not the owner or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed, or `invalid_csv`' do
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

  path '/api/v1/users/{user_id}/completionator_imports/active' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCompletionatorImport owner user_id.'

    get "Get the user's active or paused import" do
      tags 'Completionator Imports'
      description 'Owner-only. Returns the user\'s active or paused import, if any, for resuming ' \
                  'after a bot restart, or 404 if none exists.'
      produces 'application/json'

      response '200', 'active import' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionatorImport' } }
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

  path '/api/v1/completionator_imports/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCompletionatorImport import_id.'

    get 'Show a Completionator import job' do
      tags 'Completionator Imports'
      description 'Owner-only.'
      produces 'application/json'

      response '200', 'import job' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionatorImport' } }
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

    patch 'Update a Completionator import job' do
      tags 'Completionator Imports'
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
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionatorImport' } }
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

  path '/api/v1/completionator_imports/{id}/summary' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCompletionatorImport import_id.'

    get 'Summarize a Completionator import job' do
      tags 'Completionator Imports'
      description "Owner-only. Item counts grouped by status, replacing the bot's countItemsByStatus."
      produces 'application/json'

      response '200', 'summary' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionatorImportSummary' } }
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

  path '/api/v1/completionator_imports/{id}/items/next_pending' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCompletionatorImport import_id.'

    get 'Get the next pending import item' do
      tags 'Completionator Imports'
      description 'Owner-only. Returns the next pending item ordered by row_index, or `data: null` ' \
                  'once every row has been processed.'
      produces 'application/json'

      response '200', 'next pending item, or null' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionatorImportItem' } }
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

  path '/api/v1/completionator_imports/{id}/advance' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCompletionatorImport import_id.'

    post 'Advance the Completionator review loop' do
      tags 'Completionator Imports'
      description 'Owner-only (#291). Works through the pending items by row_index: each row is matched ' \
                  '(its gamedb_game_id, else the fallback title matcher; a single candidate auto-matches). ' \
                  'With no existing completion and a resolved platform the completion is auto-added; with ' \
                  'an existing completion and nothing to update the row is auto-skipped. It stops at the ' \
                  'first row that needs the member and returns its review (`next_step` choose_game, ' \
                  'add_completion, confirm_same or update_completion) in the collection CSV review shape. ' \
                  '`item` is null after 25 automatic rows (the import stays active: call again) or when ' \
                  'nothing is left (the import is marked completed). 409 `import_not_active` unless the ' \
                  'import is active. Rolled back if the import is in test_mode.'
      produces 'application/json'

      response '200', 'review of the next row needing the member' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionatorImportReview' } }
      end

      response '403', 'forbidden — caller is not the owner or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'import not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', '`import_not_active`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
