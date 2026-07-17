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
    items: { type: :array, items: { type: :object, properties: create_item_writable },
             description: 'The parsed Completionator export rows to import, in order.' }
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
                  'and inserts all row items — given as `items` — in one call.'
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
                  'checkpoint (`current_index`) as the bot works through the items.'
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
end
