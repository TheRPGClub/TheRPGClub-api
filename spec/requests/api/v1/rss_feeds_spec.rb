# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/rss_feeds', type: :request do
  # The client-writable RpgClubRssFeed columns. `feed_id` and the timestamps are
  # server-managed.
  writable = {
    feed_url: { type: :string, description: 'The RSS feed URL. Required on create.' },
    channel_id: { type: :string, description: 'Channel to post new items in. Required on create.' },
    feed_name: { type: :string, nullable: true, description: 'Optional display name for the feed.' },
    include_keywords: { type: :string, nullable: true, description: 'Optional include-keyword filter.' },
    exclude_keywords: { type: :string, nullable: true, description: 'Optional exclude-keyword filter.' }
  }

  path '/api/v1/rss_feeds' do
    get 'List RSS feeds' do
      tags 'RSS Feeds'
      description 'Open to any authenticated caller. Ordered by feed name.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'rss feeds' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/RssFeed' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create an RSS feed' do
      tags 'RSS Feeds'
      description 'Open to any authenticated caller. `feed_url` and `channel_id` are required; ' \
                  '`feed_name` and the keyword filters are optional.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[feed_url channel_id] } },
        required: %w[data]
      }

      response '201', 'feed created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/RssFeed' } }
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
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/RssFeed' } }
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
      description 'Partial update: send any subset of the writable columns.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/RssFeed' } }
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
      description 'Alias for PATCH (applied as a partial assign).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/RssFeed' } }
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
