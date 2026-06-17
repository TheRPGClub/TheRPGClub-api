# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/search_synonyms', type: :request do
  # The client-writable GamedbSearchSynonym columns. `term_id` is an auto PK and
  # `created_at` is server-managed. `term_norm` is the caller-supplied lookup key
  # (not derived server-side).
  writable = {
    group_id: { type: :integer, description: 'Synonym group this term belongs to. Required on create.' },
    term_text: { type: :string, description: 'The synonym term. Required on create.' },
    term_norm: { type: :string, description: 'Normalised lookup key (caller-supplied). Required on create.' },
    created_by: { type: :string, nullable: true, description: 'Optional creator id.' }
  }

  path '/api/v1/search_synonyms' do
    get 'List search synonym terms' do
      tags 'Search Synonyms'
      description 'Game-search synonym terms. Pass `group_id` to list the terms in one synonym group.'
      produces 'application/json'
      parameter name: :group_id, in: :query, schema: { type: :integer }, required: false,
        description: 'Filter to a single synonym group.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'synonym terms' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/SearchSynonym' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a synonym term' do
      tags 'Search Synonyms'
      description 'Restricted to admins or the service account. The caller supplies `term_norm` ' \
                  '(the normalised lookup key); it is not derived server-side.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[group_id term_text term_norm] } },
        required: %w[data]
      }

      response '201', 'term created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SearchSynonym' } }
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

  path '/api/v1/search_synonyms/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbSearchSynonym term_id.'

    get 'Show a synonym term' do
      tags 'Search Synonyms'
      produces 'application/json'

      response '200', 'term detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SearchSynonym' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a synonym term' do
      tags 'Search Synonyms'
      description 'Restricted to admins or the service account.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SearchSynonym' } }
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

    put 'Replace a synonym term (alias)' do
      tags 'Search Synonyms'
      description 'Restricted to admins or the service account.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SearchSynonym' } }
      end

      response '403', 'forbidden — admin or service required' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a synonym term' do
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
