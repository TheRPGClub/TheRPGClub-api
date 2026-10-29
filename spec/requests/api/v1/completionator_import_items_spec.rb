# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/completionator_import_items', type: :request do
  # The client-writable RpgClubCompletionatorImportItem columns for the match /
  # outcome the bot's matcher records after processing a row. `import_id`,
  # `row_index` and the source export fields are set at create time and not
  # editable here.
  update_writable = {
    status: { type: :string, enum: %w[pending added updated skipped failed], description: 'New item status.' },
    gamedb_game_id: { type: :integer, nullable: true },
    completion_id: { type: :integer, nullable: true, description: 'The UserGameCompletion entry created for this row.' },
    error_text: { type: :string, nullable: true }
  }

  path '/api/v1/completionator_import_items/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCompletionatorImportItem item_id.'

    get 'Show a Completionator import item' do
      tags 'Completionator Imports'
      description 'Owner-only (resolved through the parent import).'
      produces 'application/json'

      response '200', 'import item' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionatorImportItem' } }
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

    patch 'Update a Completionator import item' do
      tags 'Completionator Imports'
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
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionatorImportItem' } }
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

  path '/api/v1/completionator_import_items/{id}/match' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCompletionatorImportItem item_id.'

    post 'Match a game to a Completionator import item' do
      tags 'Completionator Imports'
      description 'Owner-only (#291); the import must be active and the item pending (else 409). Sets the item\'s ' \
                  'game from `game_id`, or from `igdb_id` (imported into GameDB first if needed; that import is ' \
                  'rolled back with the rest in test_mode), and returns the same review payload as advance, applying the ' \
                  'automatic step (`next_step` auto_added / auto_skipped). Rolled back if the import is in test_mode.'
      produces 'application/json'
      consumes 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: { game_id: { type: :integer }, igdb_id: { type: :integer } } } }
      }


      response '200', 'review of the matched item' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionatorImportReview' } }
      end

      response '409', '`import_not_active` or `item_not_pending`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', '`game_id_or_igdb_id_required`, `invalid_igdb_id` or `igdb_not_configured`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '502', '`igdb_request_failed`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden — caller is not the owner or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'item not found, or `game_not_found` / `igdb_game_not_found`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/completionator_import_items/{id}/add_completion' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCompletionatorImportItem item_id.'

    post 'Add a completion from a Completionator import item' do
      tags 'Completionator Imports'
      description 'Owner-only (#291); the import must be active and the item pending (else 409) and matched to a game. Creates the completion; ' \
                  'omitted fields take the review form defaults and `platform_id: null` records no platform. When ' \
                  '`platform_id` is the item\'s mapped platform and the game lacks it, a WW release is created ' \
                  'first. Sets the item to `added`. Rolled back if the import is in test_mode.'
      produces 'application/json'
      consumes 'application/json'

      parameter name: :body, in: :body, required: false, schema: {
        type: :object,
        properties: { data: { type: :object, properties: {
          completion_type: { type: :string, enum: [ 'Main Story', 'Main Story + Side Content', 'Completionist' ] },
          platform_id: { type: :integer, nullable: true },
          completed_at: { type: :string, format: 'date', nullable: true, description: 'null for an unknown date.' },
          final_playtime_hours: { type: :number, nullable: true }
        } } }
      }


      response '200', 'the item, now added' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionatorImportItem' } }
      end

      response '409', '`import_not_active` or `item_not_pending`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', '`no_game_matched`, `invalid_completion_type`, `invalid_platform` or `invalid_completed_at`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden — caller is not the owner or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'item not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/completionator_import_items/{id}/update_completion' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCompletionatorImportItem item_id.'

    post 'Update the existing completion from a Completionator import item' do
      tags 'Completionator Imports'
      description 'Owner-only (#291); the import must be active and the item pending (else 409), with an existing ' \
                  'completion (from its review). ' \
                  'Copies the selected row values onto that completion and sets the item to `updated`; when none ' \
                  'of the selected fields differ, the item is skipped instead. Rolled back if the import is in ' \
                  'test_mode.'
      produces 'application/json'
      consumes 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: { fields: { type: :array, items: { type: :string, enum: %w[type date playtime] } } } } }
      }


      response '200', 'the item, now updated (or skipped)' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionatorImportItem' } }
      end

      response '409', '`import_not_active` or `item_not_pending`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', '`invalid_fields` or `no_existing_completion`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden — caller is not the owner or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'item not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/completionator_import_items/{id}/skip' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCompletionatorImportItem item_id.'

    post 'Skip a Completionator import item' do
      tags 'Completionator Imports'
      description 'Owner-only (#291); the import must be active and the item pending (else 409). Rolled back if the ' \
                  'import is in test_mode.'
      produces 'application/json'

      response '200', 'the item, now skipped' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionatorImportItem' } }
      end

      response '409', '`import_not_active` or `item_not_pending`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden — caller is not the owner or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'item not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/completionator_import_items/{id}/igdb_candidates' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubCompletionatorImportItem item_id.'

    get 'IGDB suggestions for a Completionator import item' do
      tags 'Completionator Imports'
      description 'Owner-only (#291). Imports::IgdbCandidateSearch: searches IGDB (10 results) for `q`, or the ' \
                  'item\'s title by progressive title variants. Each result is flagged `already_imported` when GameDB has that igdb_id; pass its igdb_id to match.'
      produces 'application/json'

      parameter name: :q, in: :query, schema: { type: :string }, required: false,
                description: 'Search text; defaults to the item title.'

      response '200', 'IGDB candidates' do
        schema type: :object, properties: { data: { type: :array, items: { '$ref' => '#/components/schemas/ImportIgdbCandidate' } } }
      end

      response '422', '`igdb_not_configured`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '502', '`igdb_request_failed`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden — caller is not the owner or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'item not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
