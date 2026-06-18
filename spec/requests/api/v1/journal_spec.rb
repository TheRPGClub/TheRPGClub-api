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
      description 'Games the user has journal entries for, with per-game entry counts and the last-entry timestamp. ' \
                  'One row per game, ordered by game title. The optional `game_id` and `q` filters narrow which ' \
                  'games appear (the per-game counts stay the full totals); `q` keeps games where the user has an ' \
                  'entry whose title/body matches. Entry-level / cross-user text search lives on `GET /api/v1/journal_entries`.'
      produces 'application/json'
      parameter name: :game_id, in: :query, schema: { type: :integer }, required: false,
        description: 'Filter to a single game (`gamedb_game_id`).'
      parameter name: :q, in: :query, schema: { type: :string }, required: false,
        description: 'Keep only games with an entry whose title/body matches (case-insensitive substring).'
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

  path '/api/v1/users/{user_id}/journal/status' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'Per-game journal status for a user' do
      tags 'Journal'
      description 'For each requested game id, the user\'s journal entry count and last-entry timestamp. ' \
                  'Games with no entries are omitted (treat a missing id as a zero count). Not paginated — ' \
                  'pass a bounded set of ids. Powers the journal badge/count in the game-completion list.'
      produces 'application/json'
      parameter name: 'game_ids[]', in: :query, required: false,
        schema: { type: :array, items: { type: :integer } },
        description: 'Game ids to report on (`gamedb_game_id`). Repeat the param: `game_ids[]=1&game_ids[]=2`.'

      response '200', 'per-game status list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/JournalStatus' } }
        }
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

  path '/api/v1/journal_entries' do
    get 'Search journal entries across users' do
      tags 'Journal'
      description 'Cross-user journal entry search, each entry carrying its embedded game and author. `q` is a ' \
                  'case-insensitive substring over `entry_title`/`entry_body`; the optional `game_id` and ' \
                  '`user_id` filters narrow further (set `user_id` for per-author search). With no filters this ' \
                  'lists all entries. Ordered `created_at DESC, entry_id DESC` and paginated.'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: false,
        description: 'Case-insensitive substring over `entry_title`/`entry_body`.'
      parameter name: :game_id, in: :query, schema: { type: :integer }, required: false,
        description: 'Filter to a single game (`gamedb_game_id`).'
      parameter name: :user_id, in: :query, schema: { type: :string }, required: false,
        description: 'Filter to a single author.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'journal entries list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/JournalEntryGameUser' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/journal_entries/contributors' do
    get 'List journal contributors' do
      tags 'Journal'
      description 'Users with at least one journal entry, each with their distinct journaled-game count ' \
                  '(`game_count`) and total entry count (`entry_count`), most-journaled first. Bots and ' \
                  'members who have left the server are excluded. Paginated like every other collection.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'contributors list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/JournalContributor' } },
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
