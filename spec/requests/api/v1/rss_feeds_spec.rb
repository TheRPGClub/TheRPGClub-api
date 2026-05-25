# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/rss_feeds', type: :request do
  path '/api/v1/rss_feeds' do
    get 'List RSS feeds' do
      tags 'RSS Feeds'
      produces 'application/json'
      parameter name: :limit, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :offset, in: :query, schema: { type: :integer, default: 0 }, required: false
      parameter name: :page, in: :query, schema: { type: :integer, default: 1 }, required: false

      response '200', 'rss feeds' do
        schema type: :object, properties: {
          data: { type: :array, items: { type: :object, additionalProperties: true } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create an RSS feed' do
      tags 'RSS Feeds'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: { type: :object, additionalProperties: true, description: 'RpgClubRssFeed attributes (`feed_name`, `feed_url`, `enabled`).' }
        },
        required: %w[data]
      }

      response '201', 'feed created' do
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

  path '/api/v1/rss_feeds/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubRssFeed id.'

    get 'Show an RSS feed' do
      tags 'RSS Feeds'
      produces 'application/json'

      response '200', 'feed detail' do
        schema type: :object, properties: { data: { type: :object, additionalProperties: true } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update an RSS feed' do
      tags 'RSS Feeds'
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

    put 'Replace an RSS feed (alias)' do
      tags 'RSS Feeds'
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

    delete 'Delete an RSS feed' do
      tags 'RSS Feeds'
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
