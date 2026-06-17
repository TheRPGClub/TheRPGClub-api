# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/completions', type: :request do
  # The client-writable UserGameCompletion columns. `user_id` comes from the path.
  writable = {
    gamedb_game_id: { type: :integer, description: 'The game (gamedb_games.game_id). Required on create.' },
    completion_type: { type: :string, description: 'How it was completed (e.g. "main", "100%"). Required on create.' },
    completed_at: { type: :string, format: 'date-time', nullable: true, description: 'When the game was completed.' },
    final_playtime_hrs: { type: :number, nullable: true, description: 'Final playtime in hours.' },
    platform_id: { type: :integer, nullable: true, description: 'Optional platform association.' },
    note: { type: :string, nullable: true, description: 'Optional free-text note.' }
  }

  path '/api/v1/users/{user_id}/completions' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'List a user\'s completions' do
      tags 'Completions'
      description 'Ordered by `completed_at` descending, then `created_at` descending. Open to any ' \
                  'authenticated caller.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'completions list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/CompletionEntry' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Record a completion' do
      tags 'Completions'
      description 'Owner-only. `gamedb_game_id` and `completion_type` are required; `completed_at`, ' \
                  '`final_playtime_hrs`, `platform_id` and `note` are optional.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[gamedb_game_id completion_type] } },
        required: %w[data]
      }

      response '201', 'completion created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionEntry' } }
      end

      response '403', 'forbidden — caller is not the owner' do
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

  path '/api/v1/completions/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'UserGameCompletion completion_id.'

    get 'Show a completion' do
      tags 'Completions'
      produces 'application/json'

      response '200', 'completion detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionEntry' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a completion' do
      tags 'Completions'
      description 'Owner-only. Partial update: send any subset of the writable columns.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionEntry' } }
      end

      response '403', 'forbidden — caller is not the owner' do
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

    put 'Replace a completion (alias)' do
      tags 'Completions'
      description 'Owner-only. Alias for PATCH (applied as a partial assign).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CompletionEntry' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a completion' do
      tags 'Completions'
      description 'Owner-only.'
      produces 'application/json'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedResponse'
      end

      response '403', 'forbidden — caller is not the owner' do
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
end
