# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/codex/history_events', type: :request do
  acting_user_id = {
    type: :string,
    description: 'Service only, required on every write: the Discord user id of the member the bot acts for. ' \
                 'Their stored roles decide what they may do, and the Feature Flag applies to them.'
  }
  fields = {
    title: { type: :string, maxLength: CodexEntry::TITLE_MAX, description: 'Required, up to 100 characters.' },
    occurred_on: {
      type: :string, format: :date,
      description: 'When it happened (YYYY-MM-DD), required with `date_precision`. A `month` date is stored on ' \
                   'the 1st of its month and a `year` date on 1 January, so any day in the period may be sent.'
    },
    date_precision: { type: :string, enum: CodexEntry::DATE_PRECISIONS,
                      description: 'How precisely the club remembers the date. Required with `occurred_on`.' },
    kind: { type: :string, enum: CodexEntry::KINDS, description: 'The History Event Kind. Required.' },
    rich_body: { type: :array, items: { type: :object, additionalProperties: true }, nullable: true,
                 description: 'An optional description as Plate.js content, stored as given.' },
    body: {
      type: :string, nullable: true,
      description: 'The description as Discord markdown, made from `rich_body` by the website; required ' \
                   'whenever `rich_body` is present. Mention members as `<@discord_id>`; every save pulls them ' \
                   'into `mentions`.'
    }
  }
  admins = 'Admins and Superadmins, on any History Event whoever wrote it (anyone else gets 403 "Only Admins can ' \
           'change Club History.").'
  refusal = 'Refusals carry `{ error, message }`; `message` is written for members (403 `forbidden`, 422 ' \
            '`invalid_entry`).'
  gate = 'Belongs to the Club Codex Feature: not found for non-staff in Preview and for everyone when Off; the ' \
         'service token is not gated, but a bot write gets 403 `feature_unavailable` when the Flag hides the ' \
         'Feature from the member it acts for.'
  public_gate = 'Public: no sign-in needed. A signed-out caller is treated like any non-staff member, so Club ' \
                'History is found only while the Club Codex Feature is Live (not found in Preview and Off).'
  one_entry = { type: :object, properties: { data: { '$ref' => '#/components/schemas/CodexEntry' } } }
  invalid = 'invalid_entry: a missing or over-long title, a missing or unknown kind, a missing date or ' \
            'precision, a date that is not YYYY-MM-DD, `rich_body` without `body`, or a field that is not text'

  path '/api/v1/codex/history_events' do
    get 'List History Events (Club History)' do
      tags 'Club Codex'
      description 'Club History in date order: by `occurred_on`, then id, whatever the precision. Each carries ' \
                  '`viewer` for the caller (all false signed out); the bot may name the member it reads for with ' \
                  "`acting_user_id`. #{public_gate}"
      produces 'application/json'
      security [ {}, { bearerAuth: [] } ]
      parameter name: :kind, in: :query, required: false,
        schema: { type: :string, enum: CodexEntry::KINDS }, description: 'Keep only this History Event Kind.'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'History Events' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/CodexEntry' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '400', 'invalid_kind: `kind` is not a History Event Kind' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the Feature is Off, or Preview and the caller is not an Admin or Superadmin' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Add a History Event' do
      tags 'Club Codex'
      description "#{admins} Credited to the acting member. #{refusal} #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: { type: :object, properties: { acting_user_id: acting_user_id, **fields },
                  required: %w[title occurred_on date_precision kind] }
        },
        required: %w[data]
      }

      response '201', 'added' do
        schema one_entry
      end

      response '400', 'missing `data`, or the bot named no `acting_user_id`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'not signed in' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not an Admin or Superadmin, or (bot) `feature_unavailable`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', invalid do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/codex/history_events/{id}' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    get 'Show a History Event' do
      tags 'Club Codex'
      description public_gate
      produces 'application/json'
      security [ {}, { bearerAuth: [] } ]
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }

      response '200', 'the History Event' do
        schema one_entry
      end

      response '404', 'no such History Event, or the Feature is hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Edit a History Event' do
      tags 'Club Codex'
      description "#{admins} Changes only the fields given; the author stays. Changing only `date_precision` " \
                  "moves the stored date to the start of its new period. #{refusal} #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: { acting_user_id: acting_user_id, **fields } } },
        required: %w[data]
      }

      response '200', 'edited' do
        schema one_entry
      end

      response '400', 'missing `data`, or the bot named no `acting_user_id`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'not signed in' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not an Admin or Superadmin, or (bot) `feature_unavailable`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no such History Event, or the Feature is hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', invalid do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a History Event' do
      tags 'Club Codex'
      description "#{admins} A hard delete: its mentions go with it. The bot sends `acting_user_id` as a query " \
                  "parameter. #{refusal} #{gate}"
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }

      response '200', 'deleted' do
        schema type: :object, properties: {
          data: { type: :object, properties: { id: { type: :integer }, deleted: { type: :boolean } },
                  required: %w[id deleted] }
        }
      end

      response '400', 'the bot named no `acting_user_id`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'not signed in' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not an Admin or Superadmin, or (bot) `feature_unavailable`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no such History Event, or the Feature is hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
