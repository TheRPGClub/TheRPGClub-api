# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/backlog', type: :request do
  path '/api/v1/users/{user_id}/backlog' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'List a user\'s backlog' do
      tags 'Backlog'
      description 'Ordered by `sort_order` ascending then `created_at` descending.'
      produces 'application/json'
      parameter name: :limit, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :offset, in: :query, schema: { type: :integer, default: 0 }, required: false
      parameter name: :page, in: :query, schema: { type: :integer, default: 1 }, required: false

      response '200', 'backlog list' do
        schema type: :object, properties: {
          data: { type: :array, items: { type: :object, additionalProperties: true } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Add to backlog' do
      tags 'Backlog'
      description 'Owner-only.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: { type: :object, additionalProperties: true, description: 'UserGameBacklog attributes (`gamedb_game_id`, `platform_id`, `sort_order`, `notes`).' }
        },
        required: %w[data]
      }

      response '201', 'backlog entry created' do
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

  path '/api/v1/backlog/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'UserGameBacklog entry_id.'

    get 'Show a backlog entry' do
      tags 'Backlog'
      produces 'application/json'

      response '200', 'backlog entry' do
        schema type: :object, properties: { data: { type: :object, additionalProperties: true } }
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

    put 'Replace a backlog entry (alias)' do
      tags 'Backlog'
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
