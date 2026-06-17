# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/todos', type: :request do
  # The client-writable RpgClubTodo columns. `todo_id` and the timestamps are
  # server-managed.
  writable = {
    title: { type: :string, description: 'Todo title. Required on create.' },
    details: { type: :string, nullable: true, description: 'Optional longer description.' },
    todo_category: { type: :string, description: 'Category. One of "New Features", "Improvements", "Defects", "Blocked", "Refactoring". Optional; defaults to "Improvements".' },
    category: { type: :string, description: 'Legacy duplicate of `todo_category`. Optional; defaults to "Improvements".' },
    todo_size: { type: :string, nullable: true, description: 'Optional size estimate. One of "XS", "S", "M", "L", "XL".' },
    is_completed: { type: :boolean, description: 'Whether the todo is done. Optional; defaults to false.' },
    created_by: { type: :string, nullable: true, description: 'Optional Discord id of the creator.' },
    completed_at: { type: :string, format: 'date-time', nullable: true, description: 'When it was completed.' },
    completed_by: { type: :string, nullable: true, description: 'Optional Discord id of who completed it.' }
  }

  path '/api/v1/todos' do
    get 'List todos' do
      tags 'Todos'
      description 'Returns todo items. Pass `completed=true|false` to filter by completion state. ' \
                  'Open to any authenticated caller.'
      produces 'application/json'
      parameter name: :completed, in: :query, schema: { type: :boolean }, required: false
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'todos list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Todo' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a todo' do
      tags 'Todos'
      description 'Open to any authenticated caller. `title` is required; everything else is optional.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[title] } },
        required: %w[data]
      }

      response '201', 'todo created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Todo' } }
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
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Todo' } }
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
      description 'Partial update: send any subset of the writable columns.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Todo' } }
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
      description 'Alias for PATCH (applied as a partial assign).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Todo' } }
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
