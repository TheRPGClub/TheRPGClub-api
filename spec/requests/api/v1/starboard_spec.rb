# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/starboard', type: :request do
  path '/api/v1/starboard' do
    get 'List starboard entries' do
      tags 'Starboard'
      produces 'application/json'
      parameter name: :limit, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :offset, in: :query, schema: { type: :integer, default: 0 }, required: false
      parameter name: :page, in: :query, schema: { type: :integer, default: 1 }, required: false

      response '200', 'starboard entries' do
        schema type: :object, properties: {
          data: { type: :array, items: { type: :object, additionalProperties: true } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a starboard entry' do
      tags 'Starboard'
      description 'Records a starred Discord message. Sent by the bot service principal.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: { type: :object, additionalProperties: true, description: 'RpgClubStarboardEntry attributes (`message_id`, `channel_id`, `author_id`, `content`).' }
        },
        required: %w[data]
      }

      response '201', 'entry created' do
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

  path '/api/v1/starboard/{message_id}' do
    parameter name: :message_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord message id (also the primary key for the starboard entry).'

    get 'Show a starboard entry' do
      tags 'Starboard'
      produces 'application/json'

      response '200', 'entry detail' do
        schema type: :object, properties: { data: { type: :object, additionalProperties: true } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a starboard entry' do
      tags 'Starboard'
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

    put 'Replace a starboard entry (alias)' do
      tags 'Starboard'
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

    delete 'Delete a starboard entry' do
      tags 'Starboard'
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
