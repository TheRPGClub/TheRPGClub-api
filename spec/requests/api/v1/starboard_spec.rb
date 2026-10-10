# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/starboard', type: :request do
  # The client-writable RpgClubStarboardEntry columns. `message_id` is the
  # client-supplied Discord message id (the primary key); `created_at` is
  # server-managed.
  writable = {
    message_id: { type: :string, description: 'Discord message id (primary key). Required on create.' },
    channel_id: { type: :string, description: 'Channel the message is in. Required on create.' },
    starboard_message_id: { type: :string, description: 'Id of the bot\'s mirrored starboard message. Required on create.' },
    author_id: { type: :string, description: 'Discord id of the message author. Required on create.' },
    star_count: { type: :integer, description: 'Number of star reactions. Optional; defaults to 0.' }
  }

  path '/api/v1/starboard' do
    get 'List starboard entries' do
      tags 'Starboard'
      description 'Open to any authenticated caller. Newest first.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'starboard entries' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/StarboardEntry' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a starboard entry' do
      tags 'Starboard'
      description 'Admin- or service-only (`rpg_club_starboard` is bot/Discord-maintained). ' \
                  '`message_id`, `channel_id`, `starboard_message_id` and `author_id` are required; ' \
                  '`star_count` is optional (defaults to 0).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: { type: :object, properties: writable, required: %w[message_id channel_id starboard_message_id author_id] }
        },
        required: %w[data]
      }

      response '201', 'entry created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/StarboardEntry' } }
      end

      response '403', 'forbidden — admin or service principal required' do
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

  path '/api/v1/starboard/{message_id}' do
    parameter name: :message_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord message id (also the primary key for the starboard entry).'

    get 'Show a starboard entry' do
      tags 'Starboard'
      produces 'application/json'

      response '200', 'entry detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/StarboardEntry' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a starboard entry' do
      tags 'Starboard'
      description 'Admin- or service-only. Partial update (any subset of the writable columns) — ' \
                  'typically bumps `star_count`.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/StarboardEntry' } }
      end

      response '403', 'forbidden — admin or service principal required' do
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

    put 'Replace a starboard entry (alias)' do
      tags 'Starboard'
      description 'Admin- or service-only. Alias for PATCH (applied as a partial assign).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/StarboardEntry' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a starboard entry' do
      tags 'Starboard'
      description 'Admin- or service-only.'
      produces 'application/json'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedResponse'
      end

      response '403', 'forbidden — admin or service principal required' do
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
