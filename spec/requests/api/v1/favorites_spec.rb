# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/favorites', type: :request do
  # The client-writable UserGameFavorite columns. `user_id` comes from the path.
  writable = {
    gamedb_game_id: { type: :integer, description: 'The game (gamedb_games.game_id). Required on create. Unique per (user, game).' },
    sort_order: { type: :integer, nullable: true, description: 'Optional manual sort position.' },
    note: { type: :string, nullable: true, description: 'Optional free-text note.' }
  }
  # Update also takes `position`, the single-move reorder (spec api#451 story 15).
  update_writable = writable.merge(
    position: { type: :integer, minimum: 1,
                description: 'Moves the entry to this 1-based place in the member\'s list (past the end means ' \
                             'last) and renumbers the whole list `sort_order` 1..n in display order, in one ' \
                             'transaction. Use this to reorder; not combinable with `sort_order` ' \
                             '(422 `invalid_position`).' }
  )

  path '/api/v1/users/{user_id}/favorites' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'List a user\'s favorites' do
      tags 'Favorites'
      description 'Ordered by `sort_order` ascending (nulls last), then `created_at` descending. Open to any ' \
                  'authenticated caller. The optional `game_id` narrows to one game (`meta.count` stays exact ' \
                  'for the filtered set).'
      produces 'application/json'
      parameter name: :game_id, in: :query, schema: { type: :integer }, required: false,
        description: 'Filter to favorites of this game (`gamedb_game_id`). A non-integer matches nothing.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      parameter name: :sort, in: :query, schema: { type: :string, enum: %w[most_played] }, required: false,
        description: '`most_played` orders by the member\'s Playtime for the game (most first, none as 0), then ' \
                     'title, then the entry id. Absent keeps the list\'s own order; any other value is 422 ' \
                     '`invalid_sort`. Each item carries `playtime_minutes` either way.'

      response '200', 'favorites list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/FavoriteEntry' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '422', 'invalid_sort' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Add a favorite' do
      tags 'Favorites'
      description 'Owner-only. `gamedb_game_id` is required and must be unique per user (a game ' \
                  'can be favorited only once); `sort_order` and `note` are optional.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[gamedb_game_id] } },
        required: %w[data]
      }

      response '201', 'favorite created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/FavoriteEntry' } }
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

  path '/api/v1/favorites/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'UserGameFavorite entry_id.'

    get 'Show a favorite' do
      tags 'Favorites'
      produces 'application/json'

      response '200', 'favorite detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/FavoriteEntry' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a favorite' do
      tags 'Favorites'
      description 'Owner-only. Partial update: send any subset of the writable columns. A `position` moves the entry within the member\'s list and renumbers the rest server-side.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: update_writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/FavoriteEntry' } }
      end

      response '403', 'forbidden — caller is not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed, or `invalid_position`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    put 'Replace a favorite (alias)' do
      tags 'Favorites'
      description 'Owner-only. Alias for PATCH (applied as a partial assign).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: update_writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/FavoriteEntry' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a favorite' do
      tags 'Favorites'
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
