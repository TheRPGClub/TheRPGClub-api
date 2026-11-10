# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/news_items', type: :request do
  gate = 'Belongs to the News Hub Feature: a member who cannot use it (Preview: Admins and Superadmins only; ' \
         'Off: nobody) gets 404 `not_found`. The service token is not gated; the bot runs its own feature gate.'

  path '/api/v1/news_items' do
    get 'The News Hub feed' do
      tags 'News Hub'
      description 'News Items that have a News Category, newest first (`posted_at` descending), paged with ' \
                  '`page`/`per`. An imported News Item staff have not sorted yet is never returned. ' \
                  '`category` narrows the feed to the given News Category keys (see `GET /api/v1/news_categories`): ' \
                  'comma-separated (`category=releases,industry`) or repeated (`category[]=releases&' \
                  'category[]=industry`); an unknown key is a 400. Without `category`, the feed is the ' \
                  "member's default view: every News Category except the ones they switched off with a News " \
                  'Category Preference. With `category`, exactly those News Categories are returned, switched ' \
                  'off or not, so a preference never blocks anything. `q` searches the link title and the ' \
                  'comment (case-insensitive substring) and combines with `category`. `meta` adds, for the ' \
                  "page's category rail, `category_counts` (every News Category's count over the search alone) " \
                  'and `hidden_categories` (the switched-off keys). Each item names its author by their current ' \
                  'member name, or by the name recorded with the message when they have no member record. ' \
                  'An image whose Discord address has expired comes back unavailable (`url` null) and queues ' \
                  'a `news_images_renew` bot job for its message (one at a time per message); a later load ' \
                  'serves it once the bot has recorded fresh addresses. ' \
                  "#{gate}"
      produces 'application/json'
      parameter name: :category, in: :query, required: false,
        schema: { type: :string, example: 'releases,industry' },
        description: "Comma-separated News Category keys (any of #{NewsCategory.keys.join(', ')}). Omit for " \
                     "the member's default view (every News Category they have not switched off)."
      parameter name: :q, in: :query, required: false, schema: { type: :string, example: 'zelda' },
        description: 'Search text, matched case-insensitively anywhere in the link title or the comment. ' \
                     'Blank means no search.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'a page of News Items' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/NewsItem' } },
          meta: { '$ref' => '#/components/schemas/NewsFeedMeta' }
        }, required: %w[data meta]
      end

      response '400', 'an unknown News Category key, e.g. `{ "error": "unknown category: piracy" }`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the viewer cannot use the News Hub Feature' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/news_items/{message_id}' do
    parameter name: :message_id, in: :path, schema: { type: :string }, required: true,
      description: "The Discord message's snowflake."

    put 'Record a News Item' do
      tags 'News Hub'
      description 'Service-only. The bot records a Discord message that is a News Item (posted by a member in ' \
                  "a News Category's thread, with a link, an image attachment, or both) when it is posted and " \
                  'again whenever it is edited, including when Discord delivers the link preview a moment ' \
                  'later. Creates the News Item (201) or updates the one with this message id (200), so ' \
                  'repeating a call changes nothing. Every field is replaced by what is sent: send the whole ' \
                  'message each time. A new News Item has origin `live`. An imported News Item (origin ' \
                  '`import`) keeps its origin and the News Category staff assigned it; `category_key` is ' \
                  'ignored for it and may be omitted. A message with neither a link nor an image is not a ' \
                  'News Item and is refused (422): when an edit removes them, DELETE the News Item instead. ' \
                  'Recording works whatever the Feature Flag says.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              channel_id: { type: :string, description: "The thread's (channel's) snowflake. Required." },
              category_key: { type: :string, enum: NewsCategory.keys, nullable: true,
                              description: "The News Category of the thread the message is in. Required for a " \
                                           'live News Item; ignored for an imported one.' },
              author_id: { type: :string, description: "The author's Discord user id. Required." },
              author_name: { type: :string, maxLength: 100,
                             description: "The author's display name now, kept as the name to show if they " \
                                          'have no member record. Required.' },
              comment: { type: :string, nullable: true,
                         description: 'The message text as a reader sees it (mentions and custom emoji ' \
                                      'resolved to readable text), with the link address removed. Blank or ' \
                                      'null for none.' },
              posted_at: { type: :string, format: 'date-time', description: 'When it was posted. Required.' },
              edited_at: { type: :string, format: 'date-time', nullable: true,
                           description: 'When it was last edited; null if never.' },
              link: {
                type: :object, nullable: true,
                description: "The message's first link and Discord's preview of it; null or omitted for none. " \
                             'Further links stay in `comment`. Preview fields are null until the preview ' \
                             'arrives.',
                properties: {
                  url: { type: :string, description: 'http(s) address. Required when `link` is sent.' },
                  title: { type: :string, nullable: true },
                  site_name: { type: :string, nullable: true },
                  description: { type: :string, nullable: true },
                  image_url: { type: :string, nullable: true,
                               description: "The outside site's own image address (http(s)) from the preview." }
                },
                required: %w[url]
              },
              images: {
                type: :array,
                description: 'Every image attachment, in order; empty or omitted for none. Other attachments ' \
                             'are not sent.',
                items: {
                  type: :object,
                  properties: {
                    url: { type: :string, description: "The attachment's Discord address (http(s))." },
                    expires_at: { type: :string, format: 'date-time', nullable: true,
                                  description: "When that address expires (the `ex` parameter of Discord's " \
                                               'signed URL); null when the address has no `ex` parameter, so ' \
                                               'it does not expire and is never renewed.' }
                  },
                  required: %w[url expires_at]
                }
              }
            },
            required: %w[channel_id author_id author_name posted_at]
          }
        },
        required: %w[data]
      }

      response '201', 'News Item recorded' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/NewsItem' } }, required: %w[data]
      end

      response '200', 'News Item updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/NewsItem' } }, required: %w[data]
      end

      response '400', 'missing `data` object' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'not a News Item (no link and no image), an unknown or missing News Category, or an ' \
                      'invalid field' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden - caller is not the service principal' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Remove a News Item' do
      tags 'News Hub'
      description 'Service-only. The bot removes the News Item when its message is deleted (singly or in ' \
                  'bulk) or edited so it no longer has a link or an image. A hard delete. Idempotent: 204 ' \
                  'whether or not a News Item with this message id was recorded.'

      response '204', 'News Item removed (or was never recorded)' do
      end

      response '403', 'forbidden - caller is not the service principal' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
