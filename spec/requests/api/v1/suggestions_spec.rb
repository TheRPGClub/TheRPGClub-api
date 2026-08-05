# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/suggestions', type: :request do
  # The client-writable RpgClubSuggestion columns. `suggestion_id` and the
  # timestamps are server-managed.
  writable = {
    title: { type: :string, description: 'Suggestion title. Required on create.' },
    details: { type: :string, nullable: true, description: 'Optional longer description.' },
    labels: { type: :string, nullable: true, description: 'Optional labels (free-form string).' },
    created_by: { type: :string, nullable: true, description: 'Optional Discord user id of the author.' },
    created_by_name: { type: :string, nullable: true, description: 'Optional display name of the author.' }
  }

  path '/api/v1/suggestions' do
    get 'List suggestions' do
      tags 'Suggestions'
      description 'Open to any authenticated caller. Newest first.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'suggestions list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Suggestion' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a suggestion' do
      tags 'Suggestions'
      description 'Open to any authenticated caller. `title` is required; everything else is optional.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[title] } },
        required: %w[data]
      }

      response '201', 'suggestion created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Suggestion' } }
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/suggestions/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubSuggestion id.'

    get 'Show a suggestion' do
      tags 'Suggestions'
      produces 'application/json'

      response '200', 'suggestion detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Suggestion' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a suggestion' do
      tags 'Suggestions'
      description 'Admin- or service-only (any authenticated caller may create a suggestion, but ' \
                  'deleting one is restricted so a member cannot remove another member\'s suggestion).'
      produces 'application/json'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedResponse'
      end

      response '403', 'forbidden — admin or service principal required' do
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
