# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/now_playing', type: :request do
  # The client-writable UserNowPlaying columns. `user_id` comes from the path on
  # create; `sort_order` is server-assigned on create (appended last) but
  # client-settable on update; `added_at`/`note_updated_at` are server-managed.
  create_writable = {
    gamedb_game_id: { type: :integer, description: 'The game (gamedb_games.game_id). Required on create.' },
    platform_id: { type: :integer, nullable: true, description: 'Optional platform association.' },
    note: { type: :string, nullable: true, description: 'Optional free-text note (max 500 chars).' }
  }
  update_writable = {
    note: { type: :string, nullable: true, description: 'Free-text note (max 500 chars).' },
    platform_id: { type: :integer, nullable: true, description: 'Platform association.' },
    sort_order: { type: :integer, nullable: true, description: 'Ascending display order.' }
  }

  path '/api/v1/users/{user_id}/now_playing' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'List a user\'s now-playing games' do
      tags 'Now Playing'
      description 'The games a specific user is currently playing, ordered by `sort_order` ascending ' \
                  '(nulls last), then newest first. Open to any authenticated caller.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'now-playing list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/NowPlayingEntry' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Add a now-playing entry' do
      tags 'Now Playing'
      description 'Owner-only. Adds a game to the user\'s now-playing list. `gamedb_game_id` is ' \
                  'required; `platform_id` and `note` are optional. `sort_order` is assigned ' \
                  'server-side (appended last) and the per-user maximum of 10 entries is enforced.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: create_writable, required: %w[gamedb_game_id] } },
        required: %w[data]
      }

      response '201', 'entry created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/NowPlayingEntry' } }
      end

      response '403', 'forbidden — caller is not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed (duplicate game, max entries reached, or note too long)' do
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

  path '/api/v1/now_playing' do
    get 'List all members\' now-playing entries' do
      tags 'Now Playing'
      description 'Service/admin-only. Every active member\'s now-playing entries (bots and members ' \
                  'who have left are excluded), each with its embedded user, game and platform. The ' \
                  'optional `game_ids[]` filter narrows to entries of any of the given games; `q` keeps ' \
                  'entries whose game title matches (case-insensitive substring) for the search ' \
                  'autocomplete.'
      produces 'application/json'
      parameter name: 'game_ids[]', in: :query, required: false,
        schema: { type: :array, items: { type: :integer } }, collectionFormat: :multi,
        description: 'Filter to entries of any of these games (`gamedb_game_id`).'
      parameter name: :q, in: :query, schema: { type: :string }, required: false,
        description: 'Filter by game title (case-insensitive substring).'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'now-playing entries across members' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/NowPlayingMemberEntry' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '403', 'forbidden — caller is not service/admin' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/now_playing/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
      description: 'UserNowPlaying entry_id.'

    get 'Show a now-playing entry' do
      tags 'Now Playing'
      produces 'application/json'

      response '200', 'entry detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/NowPlayingMemberEntry' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a now-playing entry' do
      tags 'Now Playing'
      description 'Owner-only. Partial update of `note`, `platform_id` and/or `sort_order`. ' \
                  '`note_updated_at` is stamped server-side when the note changes.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: update_writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/NowPlayingMemberEntry' } }
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

    put 'Replace a now-playing entry (alias)' do
      tags 'Now Playing'
      description 'Owner-only. Alias for PATCH (applied as a partial assign).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: update_writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/NowPlayingMemberEntry' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a now-playing entry' do
      tags 'Now Playing'
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
