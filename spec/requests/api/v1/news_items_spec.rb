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
                  'a `news_images_renew` bot job for its message: one at a time per message, none within six ' \
                  "hours of that message's last renewal ending, and none for the service token's own reads; " \
                  'a later load serves it once the bot has recorded fresh addresses. An image recorded with ' \
                  'no expiry (`expires_at` null) is always served. ' \
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

  path '/api/v1/news_items/uncopied' do
    get 'News Items without a News Copy' do
      tags 'News Hub'
      description 'Service-only. The News Items that have a News Category but no News Copy yet, live and ' \
                  'imported alike, oldest first (`posted_at` ascending, then the order they were recorded), ' \
                  "paged with `page`/`per`. The bot's history copy and its retries of failed copies work " \
                  'through them, reporting each copy with `PUT /api/v1/news_items/{message_id}` and ' \
                  '`{ "data": { "news_copy": { ... } } }`; a reported item leaves the listing, so a run that ' \
                  'copies as it goes reads the first page again rather than the next. Imported News Items ' \
                  'staff have not sorted are left out. Answers whatever the Feature Flag says.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'a page of News Items without a News Copy' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/NewsItem' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }, required: %w[data meta]
      end

      response '403', 'forbidden - caller is not the service principal' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/news_items/{message_id}' do
    parameter name: :message_id, in: :path, schema: { type: :string }, required: true,
      description: "The Discord message's snowflake."

    put 'Record a News Item' do
      tags 'News Hub'
      description 'Service-only. The bot records a Discord message that is a News Item (posted in the News ' \
                  'Channel with a link, an image attachment, or both) when it is posted and again whenever it ' \
                  'is edited, including when Discord delivers the link preview a moment later. Creates the ' \
                  'News Item (201) or updates the one with this message id (200), so repeating a call changes ' \
                  'nothing. The message fields are replaced by what is sent: send the whole message each ' \
                  'time. `category_key`, `picked_category_key` and `news_copy` keep their stored values when ' \
                  'omitted on an update (send `news_copy: null` to record that the News Copy is gone); a new ' \
                  'live News Item needs `category_key`. A new News Item has origin `live`. An imported News ' \
                  'Item (origin `import`) keeps its origin and the News Category staff assigned it; ' \
                  '`category_key` is ignored for it and may be omitted. A message with neither a link nor an ' \
                  'image is not a News Item and is refused (422): when an edit removes them, DELETE the News ' \
                  'Item instead. ' \
                  'A body holding only `news_copy` reports where the News Copy of a recorded News Item ' \
                  '(live or imported) lives and changes nothing else (200, or 404 when the message was never ' \
                  'recorded). Recording works whatever the Feature Flag says.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              channel_id: { type: :string, description: "The channel's snowflake. Required unless only " \
                                                       '`news_copy` is sent.' },
              category_key: { type: :string, enum: NewsCategory.keys, nullable: true,
                              description: "The News Item's News Category. Required for a new live News " \
                                           'Item; kept when omitted on an update; ignored for an imported ' \
                                           'one.' },
              picked_category_key: { type: :string, enum: NewsCategory.keys, nullable: true,
                                     description: 'The News Category the bot picked for the message. Optional; ' \
                                                  'kept when omitted.' },
              news_copy: {
                type: :object, nullable: true,
                description: 'Where the News Copy lives, once the bot has posted it. Optional; kept when ' \
                             'omitted; null records that the News Item has no News Copy. Sent alone, it ' \
                             'reports the location without changing anything else.',
                properties: {
                  message_id: { type: :string, description: "The News Copy's Discord message id." },
                  thread_id: { type: :string, description: "The id of the News Category's thread it is in." }
                },
                required: %w[message_id thread_id]
              },
              author_id: { type: :string, description: "The author's Discord user id. Required unless only " \
                                                      '`news_copy` is sent.' },
              author_name: { type: :string, maxLength: 100,
                             description: "The author's display name now, kept as the name to show if they " \
                                          'have no member record. Required unless only `news_copy` is sent.' },
              comment: { type: :string, nullable: true,
                         description: 'The message text as a reader sees it (mentions and custom emoji ' \
                                      'resolved to readable text), with the link address removed. Blank or ' \
                                      'null for none.' },
              posted_at: { type: :string, format: 'date-time',
                           description: 'When it was posted. Required unless only `news_copy` is sent.' },
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
            description: 'The whole message (`channel_id`, `author_id`, `author_name` and `posted_at` ' \
                         'required), or only `news_copy`.'
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

      response '404', 'only `news_copy` was sent and no News Item has this message id' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'not a News Item (no link and no image), an unknown or missing News Category, an unknown ' \
                      'picked category, a `news_copy` without both ids, or an invalid field' do
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
