# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/suggestions/review_sessions', type: :request do
  # The client-writable RpgClubSuggestionReviewSession columns. `session_id` is
  # the client-supplied primary key; timestamps are server-managed.
  writable = {
    session_id: { type: :string, description: 'Client-supplied session id (primary key). Required on create.' },
    reviewer_id: { type: :string, description: 'Reviewer (Discord user id). Required on create.' },
    suggestion_ids: { type: :string, description: 'JSON-encoded array of suggestion ids under review, stored and returned verbatim. Required on create.' },
    current_index: { type: :integer, description: 'Reviewer progress index. Optional; defaults to 0.' },
    total_count: { type: :integer, description: 'Total suggestions in the session. Optional; defaults to 0.' }
  }

  path '/api/v1/suggestions/review_sessions' do
    get 'List suggestion review sessions' do
      tags 'Suggestion Review Sessions'
      description 'Lists review sessions, newest first. Pass `reviewer_id` to scope the ' \
                  'list to a single reviewer. `suggestion_ids` is returned verbatim as the ' \
                  'stored JSON string.'
      produces 'application/json'
      parameter name: :reviewer_id, in: :query, schema: { type: :string }, required: false,
        description: 'Filter to one reviewer (Discord user id).'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'review sessions list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/SuggestionReviewSession' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a review session' do
      tags 'Suggestion Review Sessions'
      description 'Admin/service-only. Creates a review session. The body carries ' \
                  '`session_id`, `reviewer_id`, `suggestion_ids` (a JSON string of suggestion ' \
                  'ids), `current_index`, and `total_count`.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[session_id reviewer_id suggestion_ids] } },
        required: %w[data]
      }

      response '201', 'review session created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SuggestionReviewSession' } }
      end

      response '403', 'forbidden — caller is not an admin or service' do
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

    delete 'Delete all review sessions for a reviewer' do
      tags 'Suggestion Review Sessions'
      description 'Admin/service-only. Deletes every review session belonging to a reviewer. ' \
                  '`reviewer_id` is required.'
      produces 'application/json'
      parameter name: :reviewer_id, in: :query, schema: { type: :string }, required: true,
        description: 'The reviewer (Discord user id) whose sessions are removed.'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedCountResponse'
      end

      response '403', 'forbidden — caller is not an admin or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing `reviewer_id`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/suggestions/review_sessions/expired' do
    delete 'Prune expired review sessions' do
      tags 'Suggestion Review Sessions'
      description 'Service-only maintenance route. Deletes sessions created before the cutoff. ' \
                  'The cutoff is the optional `before` (ISO-8601) param; when absent it defaults ' \
                  "to the bot's 15-minute TTL."
      produces 'application/json'
      parameter name: :before, in: :query, schema: { type: :string, format: 'date-time' }, required: false,
        description: 'ISO-8601 cutoff; sessions created before this are deleted. Defaults to 15 minutes ago.'

      response '200', 'pruned' do
        schema '$ref' => '#/components/schemas/DeletedCountResponse'
      end

      response '403', 'forbidden — caller is not the service principal' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/suggestions/review_sessions/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'RpgClubSuggestionReviewSession session_id.'

    get 'Show a review session' do
      tags 'Suggestion Review Sessions'
      produces 'application/json'

      response '200', 'review session detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SuggestionReviewSession' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a review session' do
      tags 'Suggestion Review Sessions'
      description 'Admin/service-only. Updates a review session — e.g. advances `current_index` ' \
                  'or rewrites `suggestion_ids` as the reviewer works through the queue.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SuggestionReviewSession' } }
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

    put 'Replace a review session (alias)' do
      tags 'Suggestion Review Sessions'
      description 'Admin/service-only. Alias for PATCH (applied as a partial assign).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SuggestionReviewSession' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a review session' do
      tags 'Suggestion Review Sessions'
      description 'Admin/service-only. Removes a single review session by `session_id`.'
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
