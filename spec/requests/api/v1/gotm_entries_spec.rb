# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/gotm_entries', type: :request do
  # Attributes accepted when creating a round entry. `voting_results_message_id`
  # is bot-managed delivery state set later via PATCH, so it is not a create
  # attribute (it starts NULL).
  create_writable = {
    round_number: { type: :integer, description: 'Round number this entry belongs to.' },
    month_year: { type: :string, example: 'January 2026', description: 'Human-readable month/year label for the round.' },
    game_index: { type: :integer, example: 0, description: 'Game slot within the round (0-based); unique per round.' },
    gamedb_game_id: { type: :integer, description: 'The GameDB game for this slot (gamedb_games.game_id).' },
    reddit_url: { type: :string, nullable: true, description: 'Optional link to the round\'s Reddit thread.' }
  }
  # Attributes accepted when updating a round entry. The round identity
  # (`round_number`, `month_year`, `game_index`) is fixed once created.
  update_writable = {
    reddit_url: { type: :string, nullable: true, description: 'Link to the round\'s Reddit thread.' },
    gamedb_game_id: { type: :integer, description: 'The GameDB game for this slot (gamedb_games.game_id).' },
    voting_results_message_id: { type: :string, nullable: true, description: 'Discord message id of the posted voting results.' }
  }

  path '/api/v1/gotm_entries' do
    get 'List Game of the Month entries' do
      tags 'GOTM'
      description 'Returns GOTM (Game of the Month) entries, newest round first. Use `include=game` to eager-load the related game record and its images.'
      produces 'application/json'
      parameter name: :round_number, in: :query, schema: { type: :integer }, required: false, description: 'Filter to a specific round number.'
      parameter name: :include, in: :query, schema: { type: :string, example: 'game' }, required: false,
        description: 'Comma-separated includes. Currently `game` is supported.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'GOTM entries' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/GotmEntry' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a Game of the Month entry' do
      tags 'GOTM'
      description 'Admin/service-only. Inserts one game slot for a round. A round can have several ' \
                  'games — POST once per game with an incrementing `game_index` (unique per round). ' \
                  '`voting_results_message_id` is bot-managed and set later via PATCH.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: create_writable, required: %w[round_number month_year game_index gamedb_game_id] } },
        required: %w[data]
      }

      response '201', 'entry created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GotmEntry' } }
      end

      response '403', 'forbidden — caller is not an admin or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed (missing required field or duplicate round/game_index)' do
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

  path '/api/v1/gotm_entries/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GotmEntry id.'

    get 'Show a Game of the Month entry' do
      tags 'GOTM'
      produces 'application/json'
      parameter name: :include, in: :query, schema: { type: :string, example: 'game' }, required: false

      response '200', 'GOTM entry' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GotmEntry' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a Game of the Month entry' do
      tags 'GOTM'
      description 'Admin/service-only. Updates the mutable fields (`reddit_url`, `gamedb_game_id`, ' \
                  '`voting_results_message_id`). The round identity is fixed once created.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: update_writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GotmEntry' } }
      end

      response '403', 'forbidden — caller is not an admin or service' do
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

    put 'Replace a Game of the Month entry (alias)' do
      tags 'GOTM'
      description 'Admin/service-only. Alias for PATCH.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: update_writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GotmEntry' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a Game of the Month entry' do
      tags 'GOTM'
      description 'Admin/service-only. Removes a single round/game slot.'
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
