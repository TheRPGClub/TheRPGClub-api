# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/journal', type: :request do
  # The client-writable UserGameJournalEntry columns. `user_id` comes from the path.
  writable = {
    gamedb_game_id: { type: :integer, description: 'The game (gamedb_games.game_id). Required on create.' },
    entry_body: { type: :string, description: 'The entry text. Required on create.' },
    entry_title: { type: :string, nullable: true, description: 'Optional entry title.' }
  }

  path '/api/v1/users/{user_id}/journal' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'List a user\'s journaled games' do
      tags 'Journal'
      description 'Games the user has journal entries for, with per-game entry counts and the last-entry timestamp. One row per game, ordered by game title.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'journaled games list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/JournaledGame' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Write a journal entry' do
      tags 'Journal'
      description 'Owner-only. Creates an entry for the given game.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[gamedb_game_id entry_body] } },
        required: %w[data]
      }

      response '201', 'entry created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/JournalEntryGame' } }
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

  path '/api/v1/games/{id}/journal' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbGame game_id.'

    get 'List journal entries for a game' do
      tags 'Journal'
      description 'Journal entries across users for the game. Pass `user_id` to filter to a single author.'
      produces 'application/json'
      parameter name: :user_id, in: :query, schema: { type: :string }, required: false, description: 'Filter to one author.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'journal entries list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/JournalEntryUser' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/journal_entries/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'UserGameJournalEntry entry_id.'

    get 'Show a journal entry' do
      tags 'Journal'
      produces 'application/json'

      response '200', 'entry detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/JournalEntryGame' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a journal entry' do
      tags 'Journal'
      description 'Owner-only.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/JournalEntryGame' } }
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

    put 'Replace a journal entry (alias)' do
      tags 'Journal'
      description 'Owner-only. Alias for PATCH (applied as a partial assign).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/JournalEntryGame' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a journal entry' do
      tags 'Journal'
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
