# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/backlog', type: :request do
  # The client-writable UserGameBacklog columns. `user_id` is taken from the
  # path (never the body), and `entry_id`/timestamps are server-managed.
  writable = {
    gamedb_game_id: { type: :integer, description: 'The game (gamedb_games.game_id) to add. Required on create.' },
    platform_id: { type: :integer, nullable: true, description: 'Optional platform association.' },
    sort_order: { type: :integer, nullable: true, description: 'Optional manual sort position.' },
    note: { type: :string, nullable: true, description: 'Optional free-text note.' }
  }

  path '/api/v1/users/{user_id}/backlog' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'List a user\'s backlog' do
      tags 'Backlog'
      description 'Ordered by `sort_order` ascending then `created_at` descending. Open to any ' \
                  'authenticated caller.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'backlog list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/BacklogEntry' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Add to backlog' do
      tags 'Backlog'
      description 'Owner-only (a Discord caller may only write their own backlog; the bot service ' \
                  'token may write any). `gamedb_game_id` is required; `platform_id`, `sort_order` ' \
                  'and `note` are optional.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[gamedb_game_id] } },
        required: %w[data]
      }

      response '201', 'backlog entry created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/BacklogEntry' } }
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

  path '/api/v1/backlog/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'UserGameBacklog entry_id.'

    get 'Show a backlog entry' do
      tags 'Backlog'
      produces 'application/json'

      response '200', 'backlog entry' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/BacklogEntry' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a backlog entry' do
      tags 'Backlog'
      description 'Owner-only. Partial update: send any subset of the writable columns.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/BacklogEntry' } }
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

    put 'Replace a backlog entry (alias)' do
      tags 'Backlog'
      description 'Owner-only. Alias for PATCH (the update is applied as a partial assign).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/BacklogEntry' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a backlog entry' do
      tags 'Backlog'
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
