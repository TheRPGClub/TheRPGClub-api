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
                  'original author and date; assigning again changes it. Each item whose News Category ' \
                  'changes records the acting staff member and the time of the change. `skip` deletes the item and remembers ' \
                  'the removal (counted in `removed`); `skip` for an item already removed counts ' \
                  'as removed again, so the same file can be applied twice. Values ignore case and surrounding ' \
                  'spaces. Applies to imported News Items only. Each bad row is listed in `rejections` with its ' \
                  'reason and does not stop the others: a missing or repeated message id (every occurrence is ' \
                  'rejected), a blank or invalid value, an unknown message id, a live News Item, or a News ' \
                  'Category for an item removed with `skip`. Leave rows with no value out of the request. Up ' \
                  'to 5000 rows per request. `moved` lists, in row order, the items whose News Category this ' \
                  'request changed and that have a News Copy, with where each copy lives, so the bot can move ' \
                  "those copies to their new categories' threads. #{staff}"
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
      description "How many imported News Items are sorted and unsorted, how many imported News Items staff " \
                  "removed with `skip`, and for the history copy how many News Items have a News Copy " \
                  "(`copied`) and how many with a News Category still have none (`uncopied`). #{staff}"
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
