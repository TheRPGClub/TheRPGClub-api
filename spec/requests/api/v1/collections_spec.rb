# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/collections', type: :request do
  # The client-writable UserGameCollection columns. `user_id` is taken from the
  # path; `entry_id`/timestamps are server-managed.
  writable = {
    gamedb_game_id: { type: :integer, description: 'The game (gamedb_games.game_id). Required on create.' },
    ownership_type: { type: :string, description: 'How the game is owned (e.g. "physical", "digital"). Required on create.' },
    platform_id: { type: :integer, nullable: true, description: 'Optional platform association.' },
    note: { type: :string, nullable: true, description: 'Optional free-text note.' },
    is_shared: { type: :boolean, description: 'Whether the entry is shared. Optional; defaults to false.' }
  }

  path '/api/v1/users/{user_id}/collections' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true, description: 'Owning RpgClubUser id.'

    get 'List a user\'s collections' do
      tags 'Collections'
      description 'Open to any authenticated caller. The optional filters mirror the bot\'s collection ' \
                  'search and AND together: `q` (game title, case-insensitive substring), `platform` ' \
                  '(case-insensitive substring of the platform name/abbreviation/code), `ownership_type` ' \
                  '(exact) and `game_id` (`gamedb_game_id`).'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: false,
        description: 'Filter by game title (case-insensitive substring).'
      parameter name: :platform, in: :query, schema: { type: :string }, required: false,
        description: 'Filter by platform name/abbreviation/code (case-insensitive substring).'
      parameter name: :ownership_type, in: :query, schema: { type: :string, enum: %w[Digital Physical Subscription Other] }, required: false,
        description: 'Filter by exact ownership type.'
      parameter name: :game_id, in: :query, schema: { type: :integer }, required: false,
        description: 'Filter by gamedb_games.game_id.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'collections list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/CollectionEntry' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a collection entry' do
      tags 'Collections'
      description 'Adds a game to the user\'s collection. `gamedb_game_id` and `ownership_type` ' \
                  'are required. NOTE: unlike the other user-game lists (backlog/favorites/…), ' \
                  'collection writes are currently NOT owner-restricted — any authenticated caller ' \
                  'may write to any `user_id` (tracked by the controller-hardening companion issue). ' \
                  'The created entry is always scoped to the path `user_id`. Returns the full record ' \
                  '(all columns, including `is_shared` and timestamps) plus the joined platform name/abbreviation.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[gamedb_game_id ownership_type] } },
        required: %w[data]
      }

      response '201', 'collection entry created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CollectionEntryDetail' } }
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

  path '/api/v1/users/{user_id}/collections/platform_summary' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true, description: 'Owning RpgClubUser id.'

    get 'Per-platform summary of a user\'s collection' do
      tags 'Collections'
      description 'The user\'s total entry count plus one tally per platform, ordered by count (desc) then ' \
                  'platform name. Entries with no platform collapse into a single row whose platform fields ' \
                  'are null. Open to any authenticated caller.'
      produces 'application/json'

      response '200', 'platform summary' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CollectionPlatformSummary' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/collections/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'UserGameCollection id.'

    get 'Show a collection entry' do
      tags 'Collections'
      description 'Returns the full record (all columns) plus the joined platform name/abbreviation.'
      produces 'application/json'

      response '200', 'collection entry' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CollectionEntryDetail' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a collection entry' do
      tags 'Collections'
      description 'Partial update (any subset of the writable columns). Not owner-restricted — see ' \
                  'the create note.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CollectionEntryDetail' } }
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

    put 'Replace a collection entry (alias)' do
      tags 'Collections'
      description 'Alias for PATCH (applied as a partial assign).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/CollectionEntryDetail' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a collection entry' do
      tags 'Collections'
      description 'Not owner-restricted — see the create note.'
      produces 'application/json'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedResponse'
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
