# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/threads', type: :request do
  # The mutable DiscordThread columns a write may set. The derived
  # `gamedb_game_id` is stripped by #writable_data (managed via the link
  # endpoints), and `thread_id` (the PK) is only accepted on the upsert create.
  # `is_archived` and `skip_linking` are stored as strings.
  mutable = {
    forum_channel_id: { type: :string, description: 'The forum channel the thread lives in.' },
    thread_name: { type: :string, description: 'Thread title.' },
    is_archived: { type: :string, description: 'Archived flag, stored as a string (e.g. "true"/"false").' },
    last_seen_at: { type: :string, format: 'date-time', nullable: true, description: 'When the bot last saw the thread.' },
    skip_linking: { type: :string, description: 'When set, the bot will not auto-link this thread to games.' }
  }

  path '/api/v1/games/{id}/threads' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbGame game_id.'

    get "List the Discord threads linked to a game" do
      tags 'Threads'
      description 'The Discord threads mapped to the game through `thread_game_links` ' \
                  '(a thread can link to several games), newest thread first. Each row ' \
                  'carries the thread metadata (`thread_name`, `forum_channel_id`, ' \
                  '`is_archived`, `last_seen_at`) plus a computed `jump_url` deep link. ' \
                  'Open to any authenticated caller.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'threads list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Thread' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/threads' do
    post 'Upsert a Discord thread' do
      tags 'Threads'
      description 'Admin/service-only. Upserts a thread by `thread_id` (a Discord snowflake): ' \
                  'inserts a new row, or on an existing one refreshes only `forum_channel_id`, ' \
                  '`thread_name`, `is_archived`, `last_seen_at` — `skip_linking` and `created_at` ' \
                  'are left untouched so a sync sweep can\'t clobber them. The derived ' \
                  '`gamedb_game_id` is ignored on write (managed via the link endpoints). ' \
                  '`thread_id`, `forum_channel_id` and `thread_name` are required.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: { thread_id: { type: :string, description: 'Discord thread snowflake (the PK). Required.' } }.merge(mutable),
            required: %w[thread_id forum_channel_id thread_name]
          }
        },
        required: %w[data]
      }

      response '201', 'thread created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Thread' } }
      end

      response '200', 'existing thread updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Thread' } }
      end

      response '403', 'forbidden — caller is not an admin or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing `data` or `thread_id`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/threads/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'Thread thread_id.'

    get 'Show a thread and its game links' do
      tags 'Threads'
      description 'The thread plus its full game-link list under `links` (a thread can map to ' \
                  'several games, beyond the derived `gamedb_game_id` primary).'
      produces 'application/json'

      response '200', 'thread' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/ThreadWithLinks' } }
      end

      response '404', 'thread not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a thread' do
      tags 'Threads'
      description 'Admin/service-only. Partial update of any mutable column — `skip_linking`, ' \
                  '`is_archived`, `thread_name`, `forum_channel_id`, `last_seen_at`. The PK ' \
                  '(`thread_id`) and derived `gamedb_game_id` cannot be changed.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: mutable } },
        required: %w[data]
      }

      response '200', 'thread updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Thread' } }
      end

      response '403', 'forbidden — caller is not an admin or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'thread not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/threads/{id}/links' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'Thread thread_id.'

    post 'Link a thread to a game' do
      tags 'Threads'
      description 'Admin/service-only. Idempotent merge — links the thread to the game (or ' \
                  'returns the existing link) and recomputes the thread\'s derived ' \
                  '`gamedb_game_id` (the MIN of its links). 201 when newly linked, 200 when it ' \
                  'already was.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: { gamedb_game_id: { type: :integer, description: 'The game to link (gamedb_games.game_id).' } },
            required: %w[gamedb_game_id]
          }
        },
        required: %w[data]
      }

      response '201', 'thread linked' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/ThreadGameLink' } }
      end

      response '200', 'link already existed' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/ThreadGameLink' } }
      end

      response '403', 'forbidden — caller is not an admin or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed (unknown game)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'thread not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Remove all of a thread\'s game links' do
      tags 'Threads'
      description 'Admin/service-only. Removes every game link from the thread and resets the ' \
                  'derived `gamedb_game_id` to null.'
      produces 'application/json'

      response '200', 'links removed' do
        schema '$ref' => '#/components/schemas/DeletedCountResponse'
      end

      response '403', 'forbidden — caller is not an admin or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'thread not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/threads/{id}/links/{game_id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'Thread thread_id.'
    parameter name: :game_id, in: :path, schema: { type: :integer }, required: true, description: 'GamedbGame game_id.'

    delete 'Remove one game link from a thread' do
      tags 'Threads'
      description 'Admin/service-only. Removes a single thread→game link and recomputes the ' \
                  'thread\'s derived `gamedb_game_id` (the MIN of the remaining links).'
      produces 'application/json'

      response '200', 'link removed' do
        schema '$ref' => '#/components/schemas/DeletedCountResponse'
      end

      response '403', 'forbidden — caller is not an admin or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'thread not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
