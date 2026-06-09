# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/search_synonym_drafts', type: :request do
  path '/api/v1/search_synonym_drafts' do
    get 'List synonym drafts' do
      tags 'Search Synonyms'
      description 'Per-user synonym drafts (a scratchpad of pending `{term, match}` pairs in `pairs_json`). ' \
                  'Pass `user_id` to filter to one author.'
      produces 'application/json'
      parameter name: :user_id, in: :query, schema: { type: :string }, required: false,
        description: 'Filter to drafts owned by this user.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'synonym drafts' do
        schema type: :object, properties: {
          data: { type: :array, items: { type: :object, additionalProperties: true } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a synonym draft' do
      tags 'Search Synonyms'
      description 'Restricted to admins or the service account. `pairs_json` is an opaque JSON string ' \
                  'owned by the bot (an array of `{term, match}` pairs).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: { type: :object, additionalProperties: true, description: 'GamedbSearchSynonymDraft attributes (`user_id`, `pairs_json`).' }
        },
        required: %w[data]
      }

      response '201', 'draft created' do
        schema type: :object, properties: { data: { type: :object, additionalProperties: true } }
      end

      response '403', 'forbidden — admin or service required' do
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

  path '/api/v1/search_synonym_drafts/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbSearchSynonymDraft draft_id.'

    get 'Show a synonym draft' do
      tags 'Search Synonyms'
      produces 'application/json'

      response '200', 'draft detail' do
        schema type: :object, properties: { data: { type: :object, additionalProperties: true } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a synonym draft' do
      tags 'Search Synonyms'
      description 'Restricted to admins or the service account.'
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

      response '403', 'forbidden — admin or service required' do
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

    put 'Replace a synonym draft (alias)' do
      tags 'Search Synonyms'
      description 'Restricted to admins or the service account.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, additionalProperties: true } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { type: :object, additionalProperties: true } }
      end

      response '403', 'forbidden — admin or service required' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a synonym draft' do
      tags 'Search Synonyms'
      description 'Restricted to admins or the service account.'
      produces 'application/json'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedResponse'
      end

      response '403', 'forbidden — admin or service required' do
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
