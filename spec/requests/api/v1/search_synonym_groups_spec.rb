# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/search_synonym_groups', type: :request do
  # The only client-writable GamedbSearchSynonymGroup column. `group_id` is an
  # auto PK and `created_at` is server-managed.
  writable = {
    created_by: { type: :string, nullable: true, description: 'Optional creator id.' }
  }

  path '/api/v1/search_synonym_groups' do
    get 'List synonym groups' do
      tags 'Search Synonyms'
      description 'Synonym groups — each group is an equivalence class that its terms belong to. ' \
                  'Pass `q` to search for groups by one of their terms, and `include=terms` to get ' \
                  'each group\'s terms in the same response.'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: false,
        description: 'Free-text search: returns groups having a term that matches `q` by literal ' \
                     'text (case-insensitive) or normalised key.'
      parameter name: :include, in: :query, schema: { type: :string, enum: %w[terms] }, required: false,
        description: 'Pass `terms` to embed each group\'s terms (sorted by text) under `terms`.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'synonym groups' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/SearchSynonymGroup' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a synonym group' do
      tags 'Search Synonyms'
      description 'Restricted to admins or the service account.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '201', 'group created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SearchSynonymGroup' } }
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

  path '/api/v1/search_synonym_groups/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbSearchSynonymGroup group_id.'

    get 'Show a synonym group' do
      tags 'Search Synonyms'
      produces 'application/json'
      parameter name: :include, in: :query, schema: { type: :string, enum: %w[terms] }, required: false,
        description: 'Pass `terms` to embed each group\'s terms (sorted by text) under `terms`.'

      response '200', 'group detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SearchSynonymGroup' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a synonym group' do
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
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SearchSynonymGroup' } }
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

    put 'Replace a synonym group (alias)' do
      tags 'Search Synonyms'
      description 'Restricted to admins or the service account.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SearchSynonymGroup' } }
      end

      response '403', 'forbidden — admin or service required' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a synonym group' do
      tags 'Search Synonyms'
      description 'Restricted to admins or the service account. Cascade-deletes the group\'s synonym terms.'
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

  path '/api/v1/search_synonym_groups/{id}/terms' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbSearchSynonymGroup group_id.'

    delete 'Delete all terms in a synonym group' do
      tags 'Search Synonyms'
      description 'Bulk-deletes every term in the group, leaving the group itself intact. Restricted ' \
                  'to admins or the service account. Used to atomically replace a group\'s terms ' \
                  '(delete all, then re-insert). Returns the number of terms removed.'
      produces 'application/json'

      response '200', 'terms deleted' do
        schema '$ref' => '#/components/schemas/DeletedCountResponse'
      end

      response '403', 'forbidden — admin or service required' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'group not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    put 'Replace all terms in a synonym group' do
      tags 'Search Synonyms'
      description 'Swaps every term in the group for the given list in one transaction, so the group ' \
                  'is never left half saved. Restricted to admins (Admin and up) or the service account. ' \
                  'Terms are trimmed and blanks dropped; a term that normalises like an earlier one is ' \
                  'skipped. Each term needs a letter or number and the group needs at least two different ' \
                  'terms, otherwise nothing changes and 422 is returned. A signed-in caller is recorded as ' \
                  'the terms\' creator; only the service account may pass `created_by`. Returns the group ' \
                  'with its new terms.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              terms: { type: :array, items: { type: :string }, minItems: 2,
                       description: 'The group\'s complete new term list.' },
              created_by: { type: :string, nullable: true,
                            description: 'Service account only: the creator id to record. Ignored for signed-in callers.' }
            },
            required: %w[terms]
          }
        },
        required: %w[data]
      }

      response '200', 'terms replaced' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SearchSynonymGroupWithTerms' } },
          required: %w[data]
      end

      response '400', 'data envelope missing' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden, admin or service required' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'group not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'invalid terms (not a list, a term without letters or numbers, or fewer than two)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
