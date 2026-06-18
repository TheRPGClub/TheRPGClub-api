# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/nominations', type: :request do
  # Caller-settable columns on upsert (#97). `round_number` comes from the path
  # and `nominated_at` is server-managed, so neither appears here. `user_id` is
  # the conflict key (round + user) the upsert resolves against.
  writable = {
    user_id: { type: :string, description: 'Nominator (Discord user id). Required; the (round, user) conflict key.' },
    gamedb_game_id: { type: :integer, description: 'The nominated GameDB game (gamedb_games.game_id). Required for NR-GOTM; optional for GOTM.' },
    reason: { type: :string, nullable: true, description: 'Free-text reason for the nomination.' }
  }

  path '/api/v1/gotm_entries/{round}/nominations' do
    parameter name: :round, in: :path, schema: { type: :integer }, required: true,
      description: 'GOTM voting round number.'

    get 'List GOTM nominations for a round' do
      tags 'GOTM'
      description 'The games nominated for the given GOTM voting round, oldest first, each ' \
                  'with its embedded nominator (`user`) and `game`.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'GOTM nominations' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Nomination' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Upsert a GOTM nomination' do
      tags 'GOTM'
      description 'Admin/service-only. Creates the caller-supplied user\'s nomination for the ' \
                  'round, or replaces it if they already have one (upsert on `round`+`user_id`). ' \
                  'Returns 201 when a new nomination is created, 200 when an existing one is updated.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[user_id] } },
        required: %w[data]
      }

      response '201', 'nomination created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Nomination' } }
      end

      response '200', 'existing nomination replaced' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Nomination' } }
      end

      response '403', 'forbidden — caller is not an admin or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed (missing required field)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing `data` parameter' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete all GOTM nominations for a round' do
      tags 'GOTM'
      description 'Admin/service-only. Clears every nomination for the round (the `/admin ' \
                  'delete-gotm-noms` reset before a voting round opens).'
      produces 'application/json'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedCountResponse'
      end

      response '403', 'forbidden — caller is not an admin or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/gotm_entries/{round}/nominations/{user_id}' do
    parameter name: :round, in: :path, schema: { type: :integer }, required: true,
      description: 'GOTM voting round number.'
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Nominator (Discord user id).'

    get 'Show a user\'s GOTM nomination for a round' do
      tags 'GOTM'
      description 'The single nomination for the given user in the round, with its embedded ' \
                  'nominator (`user`) and `game`, or 404 if the user has none.'
      produces 'application/json'

      response '200', 'nomination' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Nomination' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a user\'s GOTM nomination for a round' do
      tags 'GOTM'
      description 'Admin/service-only. Removes the given user\'s nomination for the round.'
      produces 'application/json'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedResponse'
      end

      response '403', 'forbidden — caller is not an admin or service' do
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

  path '/api/v1/nr_gotm_entries/{round}/nominations' do
    parameter name: :round, in: :path, schema: { type: :integer }, required: true,
      description: 'Non-RPG GOTM voting round number.'

    get 'List Non-RPG GOTM nominations for a round' do
      tags 'GOTM'
      description 'The games nominated for the given Non-RPG GOTM voting round, oldest first, ' \
                  'each with its embedded nominator (`user`) and `game`.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'Non-RPG GOTM nominations' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Nomination' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Upsert a Non-RPG GOTM nomination' do
      tags 'GOTM'
      description 'Admin/service-only. Creates the caller-supplied user\'s nomination for the ' \
                  'round, or replaces it if they already have one (upsert on `round`+`user_id`). ' \
                  'Returns 201 when a new nomination is created, 200 when an existing one is updated. ' \
                  '`gamedb_game_id` is required for NR-GOTM.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[user_id gamedb_game_id] } },
        required: %w[data]
      }

      response '201', 'nomination created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Nomination' } }
      end

      response '200', 'existing nomination replaced' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Nomination' } }
      end

      response '403', 'forbidden — caller is not an admin or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed (missing required field)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing `data` parameter' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete all Non-RPG GOTM nominations for a round' do
      tags 'GOTM'
      description 'Admin/service-only. Clears every nomination for the round (the `/admin ' \
                  'delete-nr-gotm-noms` reset before a voting round opens).'
      produces 'application/json'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedCountResponse'
      end

      response '403', 'forbidden — caller is not an admin or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/nr_gotm_entries/{round}/nominations/{user_id}' do
    parameter name: :round, in: :path, schema: { type: :integer }, required: true,
      description: 'Non-RPG GOTM voting round number.'
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Nominator (Discord user id).'

    get 'Show a user\'s Non-RPG GOTM nomination for a round' do
      tags 'GOTM'
      description 'The single nomination for the given user in the round, with its embedded ' \
                  'nominator (`user`) and `game`, or 404 if the user has none.'
      produces 'application/json'

      response '200', 'nomination' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Nomination' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a user\'s Non-RPG GOTM nomination for a round' do
      tags 'GOTM'
      description 'Admin/service-only. Removes the given user\'s nomination for the round.'
      produces 'application/json'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedResponse'
      end

      response '403', 'forbidden — caller is not an admin or service' do
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
