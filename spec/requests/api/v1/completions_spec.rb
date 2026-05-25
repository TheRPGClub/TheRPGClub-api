# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/completions', type: :request do
  path '/api/v1/users/{user_id}/completions' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'List a user\'s completions' do
      tags 'Completions'
      produces 'application/json'
      parameter name: :limit, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :offset, in: :query, schema: { type: :integer, default: 0 }, required: false
      parameter name: :page, in: :query, schema: { type: :integer, default: 1 }, required: false

      response '200', 'completions list' do
        schema type: :object, properties: {
          data: { type: :array, items: { type: :object, additionalProperties: true } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Record a completion' do
      tags 'Completions'
      description 'Owner-only. Sends the request payload under a top-level `data` key.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            additionalProperties: true,
            description: 'UserGameCompletion attributes (e.g. `gamedb_game_id`, `platform_id`, `completed_at`, `rating`, `notes`).'
          }
        },
        required: %w[data]
      }

      response '201', 'completion created' do
        schema type: :object, properties: { data: { type: :object, additionalProperties: true } }
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

  path '/api/v1/completions/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'UserGameCompletion completion_id.'

    get 'Show a completion' do
      tags 'Completions'
      produces 'application/json'

      response '200', 'completion detail' do
        schema type: :object, properties: { data: { type: :object, additionalProperties: true } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a completion' do
      tags 'Completions'
      description 'Owner-only.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, additionalProperties: true } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { type: :object, additionalProperties: true } }
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

    put 'Replace a completion (alias)' do
      tags 'Completions'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, additionalProperties: true } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { type: :object, additionalProperties: true } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a completion' do
      tags 'Completions'
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
