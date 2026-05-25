# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/todos', type: :request do
  path '/api/v1/todos' do
    get 'List todos' do
      tags 'Todos'
      description 'Returns todo items. Pass `completed=true|false` to filter by completion state.'
      produces 'application/json'
      parameter name: :completed, in: :query, schema: { type: :boolean }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :offset, in: :query, schema: { type: :integer, default: 0 }, required: false
      parameter name: :page, in: :query, schema: { type: :integer, default: 1 }, required: false

      response '200', 'todos list' do
        schema type: :object, properties: {
          data: { type: :array, items: { type: :object, additionalProperties: true } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a todo' do
      tags 'Todos'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: { type: :object, additionalProperties: true, description: 'RpgClubTodo attributes (`title`, `body`, `is_completed`).' }
        },
        required: %w[data]
      }

      response '201', 'todo created' do
        schema type: :object, properties: { data: { type: :object, additionalProperties: true } }
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/todos/summary' do
    get 'Todo counts summary' do
      tags 'Todos'
      description 'Returns counts of total, completed, and open todos.'
      produces 'application/json'

      response '200', 'summary' do
        schema type: :object, properties: {
          data: {
            type: :object,
            properties: {
              total: { type: :integer },
              completed: { type: :integer },
              open: { type: :integer }
            }
          }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/todos/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubTodo id.'

    get 'Show a todo' do
      tags 'Todos'
      produces 'application/json'

      response '200', 'todo detail' do
        schema type: :object, properties: { data: { type: :object, additionalProperties: true } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a todo' do
      tags 'Todos'
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

    put 'Replace a todo (alias)' do
      tags 'Todos'
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

    delete 'Delete a todo' do
      tags 'Todos'
      produces 'application/json'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedResponse'
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
