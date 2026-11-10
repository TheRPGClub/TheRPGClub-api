# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/news_import', type: :request do
  staff = 'The News Import works for Admins and Superadmins while the News Hub is Preview or Live, and for ' \
          'nobody while it is Off. A signed-in member is checked by their own roles; the bot calls with the ' \
          'service token and names the acting Discord user (`acting_user_id`), and the same rule applies to ' \
          'that member\'s stored roles: 400 `acting_user_id required` without one, 403 when they are not an ' \
          'Admin or Superadmin or have no member record. While Off, the News Hub Feature gate answers a ' \
          'signed-in caller 404; the service token is not gated, so the bot refuses its /news-import commands ' \
          'itself.'
  acting_query = lambda do
    parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string },
      description: 'Bot only (required with the service token): the Discord user id of the staff member who ' \
                   'ran the command.'
  end
  page_params = lambda do
    parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
    parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
  end
  error_responses = lambda do |bad_request = 'the bot named no `acting_user_id`'|
    response '400', bad_request do
      schema '$ref' => '#/components/schemas/Error'
    end
    response '401', 'unauthenticated' do
      schema '$ref' => '#/components/schemas/Error'
    end
    response '403', 'the acting member is not an Admin or Superadmin' do
      schema '$ref' => '#/components/schemas/Error'
    end
    response '404', 'a signed-in caller while the News Hub is Off' do
      schema '$ref' => '#/components/schemas/Error'
    end
  end

  path '/api/v1/news_import/items' do
    post 'Record a batch of archived messages' do
      tags 'News Hub'
      description 'Service-only. The News Import scan sends the Game News Archive\'s qualifying messages (by a ' \
                  'member, not a bot, with a link, an image attachment, or both) in batches of up to 100. Each ' \
                  'becomes an imported News Item (origin `import`) with no News Category, hidden from members ' \
                  'until staff assign one. Safe to repeat: a message already recorded is updated in place and ' \
                  'keeps any News Category staff assigned; a message staff removed with `skip` is left out ' \
                  '(`previously_removed`) and never comes back. Each message stands alone: one that is not a ' \
                  'valid News Item, or is already a live News Item, is listed in `rejected` with its reason and ' \
                  'the rest are still recorded. The fields are those of `PUT /api/v1/news_items/{message_id}` ' \
                  'plus `message_id`, without `category_key`. The service token is not gated; the bot runs the ' \
                  'scan only for an Admin or Superadmin while the News Hub is Preview or Live (nobody imports ' \
                  'while it is Off).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              items: {
                type: :array, maxItems: 100,
                items: {
                  type: :object,
                  properties: {
                    message_id: { type: :string, description: "The archived message's snowflake. Required." },
                    channel_id: { type: :string, description: "The Game News Archive's channel id. Required." },
                    author_id: { type: :string, description: "The author's Discord user id. Required." },
                    author_name: { type: :string, maxLength: 100,
                                   description: "The author's display name now (for a member who left, the " \
                                                'name Discord still shows). Required.' },
                    comment: { type: :string, nullable: true,
                               description: 'The message text as a reader sees it, without the link address.' },
                    posted_at: { type: :string, format: 'date-time',
                                 description: 'When it was originally posted. Required.' },
                    edited_at: { type: :string, format: 'date-time', nullable: true },
                    link: {
                      type: :object, nullable: true,
                      description: "The message's first link and Discord's preview of it; null for none.",
                      properties: {
                        url: { type: :string },
                        title: { type: :string, nullable: true },
                        site_name: { type: :string, nullable: true },
                        description: { type: :string, nullable: true },
                        image_url: { type: :string, nullable: true }
                      },
                      required: %w[url]
                    },
                    images: {
                      type: :array,
                      description: 'Every image attachment, in order, with its Discord address and expiry.',
                      items: {
                        type: :object,
                        properties: {
                          url: { type: :string },
                          expires_at: { type: :string, format: 'date-time', nullable: true,
                                        description: "When that address expires (the `ex` parameter of " \
                                                     "Discord's signed URL); null when the address has no " \
                                                     '`ex` parameter, so it does not expire.' }
                        },
                        required: %w[url expires_at]
                      }
                    }
                  },
                  required: %w[message_id channel_id author_id author_name posted_at]
                }
              }
            },
            required: %w[items]
          }
        },
        required: %w[data]
      }

      response '200', 'the batch was applied; counts and per-message rejections' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/NewsImportBatchResult' } },
          required: %w[data]
      end

      response '400', 'missing `data.items`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'more than 100 items, `{ "error": "at most 100 items per batch" }`; nothing was recorded' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden - caller is not the service principal' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    get 'List the unsorted imported News Items' do
      tags 'News Hub'
      description 'The imported News Items staff have not assigned a News Category yet, oldest first ' \
                  '(`posted_at`, then id), paged with `page`/`per`, with the fields a classifier needs. The bot ' \
                  "turns them into the download file. #{staff}"
      produces 'application/json'
      instance_exec(&acting_query)
      instance_exec(&page_params)

      response '200', 'a page of unsorted imported News Items' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/NewsImportItem' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }, required: %w[data meta]
      end

      instance_exec(&error_responses)
    end
  end

  path '/api/v1/news_import/assignments' do
    post 'Assign News Categories to imported News Items' do
      tags 'News Hub'
      description 'Applies a reviewed list of rows, each a message id and a value. A News Category key ' \
                  "(#{NewsCategory.keys.join(', ')}) assigns it, which shows the item to members with its " \
                  'original author and date; assigning again changes it. `skip` deletes the item and remembers ' \
                  'the removal, so a later scan never brings it back; `skip` for an item already removed counts ' \
                  'as removed again, so the same file can be applied twice. Values ignore case and surrounding ' \
                  'spaces. Applies to imported News Items only. Each bad row is listed in `rejections` with its ' \
                  'reason and does not stop the others: a missing or repeated message id (every occurrence is ' \
                  'rejected), a blank or invalid value, an unknown message id, a live News Item, or a News ' \
                  'Category for an item removed with `skip`. Leave rows with no value out of the request. Up ' \
                  "to 5000 rows per request. #{staff}"
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              acting_user_id: { type: :string,
                                description: 'Bot only (required with the service token): the Discord user id ' \
                                             'of the staff member who ran the command.' },
              rows: {
                type: :array, maxItems: 5000,
                items: {
                  type: :object,
                  properties: {
                    message_id: { type: :string },
                    value: { type: :string, example: 'releases',
                             description: "A News Category key, or `skip`." }
                  },
                  required: %w[message_id value]
                }
              }
            },
            required: %w[rows]
          }
        },
        required: %w[data]
      }

      response '200', 'the valid rows were applied; counts and per-row rejections' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/NewsImportAssignResult' } },
          required: %w[data]
      end

      response '422', 'more than 5000 rows, `{ "error": "at most 5000 rows per request" }`; nothing was applied' do
        schema '$ref' => '#/components/schemas/Error'
      end

      instance_exec('the bot named no `data.acting_user_id`, or `data.rows` is missing', &error_responses)
    end
  end

  path '/api/v1/news_import/status' do
    get 'News Import counts' do
      tags 'News Hub'
      description "How many imported News Items are sorted and unsorted, how many archive messages staff " \
                  "removed with `skip`, and the oldest message imported so far (`oldest_message_id`), where " \
                  "a re-run scan continues. #{staff}"
      produces 'application/json'
      instance_exec(&acting_query)

      response '200', 'the counts' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/NewsImportStatus' } },
          required: %w[data]
      end

      instance_exec(&error_responses)
    end
  end
end
