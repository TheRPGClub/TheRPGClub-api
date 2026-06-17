# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/rss_feeds/{rss_feed_id}/items', type: :request do
  path '/api/v1/rss_feeds/{rss_feed_id}/items' do
    parameter name: :rss_feed_id, in: :path, schema: { type: :string }, required: true,
      description: 'RpgClubRssFeed id (feed_id).'

    get 'List seen item hashes for a feed' do
      tags 'RSS Feeds'
      produces 'application/json'
      description <<~DESC.strip
        Returns the subset of the supplied candidate hashes that have already been
        recorded as seen for this feed, so the bot can dedupe RSS items without
        fetching every stored hash. The candidate list may be supplied as repeated
        `?hashes[]=` query params or, for large lists, as a JSON request body
        `{ "hashes": ["..."] }`. An empty or absent list returns `{ "data": [] }`.
      DESC

      parameter name: 'hashes[]', in: :query, required: false,
        schema: { type: :array, items: { type: :string } },
        description: 'Candidate item_id_hash values to check.'

      response '200', 'seen hashes' do
        schema type: :object, properties: {
          data: { type: :array, items: { type: :string }, description: 'item_id_hash values already seen for this feed.' }
        }
      end

      response '404', 'feed not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Bulk-mark items as seen' do
      tags 'RSS Feeds'
      consumes 'application/json'
      produces 'application/json'
      description <<~DESC.strip
        Inserts the supplied items for this feed with insert-or-ignore semantics on
        the (feed_id, item_id_hash) primary key; entries whose hash is already stored
        are skipped. Returns the number of rows actually inserted.
      DESC

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :array,
            description: 'Items to mark seen.',
            items: {
              type: :object,
              properties: {
                item_id_hash: { type: :string },
                title: { type: :string, nullable: true },
                url: { type: :string, nullable: true },
                published_at: { type: :string, format: 'date-time', nullable: true }
              },
              required: %w[item_id_hash]
            }
          }
        },
        required: %w[data]
      }

      response '201', 'items marked seen' do
        schema type: :object, properties: { created: { type: :integer, description: 'Rows actually inserted (duplicates skipped).' } }
      end

      response '404', 'feed not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
