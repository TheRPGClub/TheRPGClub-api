# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/reviews', type: :request do
  # The client-writable UserGameReview columns. `user_id` comes from the path.
  writable = {
    gamedb_game_id: { type: :integer, description: 'The game (gamedb_games.game_id). Required on create. Unique per (user, game).' },
    rating: { type: :integer, description: 'Numeric rating. Required on create.' },
    body: { type: :object, nullable: true, description: 'Optional structured review body (free-form JSON).' },
    is_shared: { type: :boolean, description: 'Whether the review is shared. Optional. Write-only — not returned by the curated game-scoped list.' }
  }

  path '/api/v1/users/{user_id}/reviews' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'List a user\'s reviews' do
      tags 'Reviews'
      description 'Open to any authenticated caller. Returns the full review records (all columns).'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'reviews list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Review' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Write a review' do
      tags 'Reviews'
      description 'Owner-only. `gamedb_game_id` and `rating` are required; a user may review a ' \
                  'given game only once (unique per (user, game)). `body` and `is_shared` are optional.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[gamedb_game_id rating] } },
        required: %w[data]
      }

      response '201', 'review created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Review' } }
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

  path '/api/v1/reviews/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'UserGameReview review_id.'

    get 'Show a review' do
      tags 'Reviews'
      produces 'application/json'

      response '200', 'review detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Review' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a review' do
      tags 'Reviews'
      description 'Owner-only. Partial update: send any subset of the writable columns.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Review' } }
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

    put 'Replace a review (alias)' do
      tags 'Reviews'
      description 'Owner-only. Alias for PATCH (applied as a partial assign).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Review' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a review' do
      tags 'Reviews'
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
