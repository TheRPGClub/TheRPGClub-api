# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/codex/lore_entries', type: :request do
  acting_user_id = {
    type: :string,
    description: 'Service only, required on every write: the Discord user id of the member the bot acts for. ' \
                 'Their stored roles decide what they may do, and the Feature Flag applies to them.'
  }
  fields = {
    title: { type: :string, maxLength: CodexEntry::TITLE_MAX,
             description: 'Required, up to 100 characters. Surrounding spaces are dropped.' },
    rich_body: { type: :array, items: { type: :object, additionalProperties: true }, nullable: true,
                 description: 'The Plate.js story, stored and returned exactly as given; the API never checks it. ' \
                              'The website sanitizes it and keeps it to 4000 characters of text.' },
    body: { type: :string,
            description: 'Required: the story as Discord markdown, which the website makes from `rich_body` on ' \
                         'every save. Mention members as `<@discord_id>`; every save pulls them into ' \
                         '`mentions`, and an id that is not a known member stays as text.' },
    occurred_on: { type: :string, format: :date, nullable: true,
                   description: 'Optional, as `YYYY-MM-DD`, given together with `date_precision` (both null for ' \
                                'none). A `month` date is stored as the 1st of its month and a `year` date as 1 ' \
                                'January, whatever day is sent.' },
    date_precision: { type: :string, enum: [ *CodexEntry::DATE_PRECISIONS, nil ], nullable: true,
                      description: 'How precise `occurred_on` is: day, month or year. Given together with it.' }
  }
  refusal = 'Refusals carry `{ error, message }`; `message` is written for members (403 `forbidden`, 422 ' \
            '`invalid_entry`).'
  invalid = 'invalid_entry: `title` blank or over 100 characters, `body` blank, a field not text, a date and ' \
            'precision not given together, an unknown precision, a date that is not `YYYY-MM-DD`, a NUL ' \
            'character in any field, or a field a Lore Entry does not take (`kind`, or any other)'
  gate = 'Belongs to the Club Codex Feature: not found for non-staff in Preview and for everyone when Off; the ' \
         'service token is not gated, but a bot write gets 403 `feature_unavailable` when the Flag hides the ' \
         'Feature from the member it acts for.'
  one_entry = { type: :object, properties: { data: { '$ref' => '#/components/schemas/CodexEntry' } } }

  path '/api/v1/codex/lore_entries' do
    get 'List Lore Entries' do
      tags 'Club Codex'
      description 'Members (any signed-in caller). Newest first. Each carries `viewer` for the acting member; the ' \
                  "bot may name the member it reads for with `acting_user_id`, without which `viewer` is all false. #{gate}"
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'Lore Entries' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/CodexEntry' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'not signed in' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the Feature is Off, or Preview and the caller is not an Admin or Superadmin' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Add a Lore Entry' do
      tags 'Club Codex'
      description 'Regulars, Moderators, Admins and Superadmins (a member without the Regulars role gets 403 ' \
                  '"You need the Regulars role to add to the Club Codex."). Published at once, credited to the ' \
                  "acting member. #{refusal} #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: { type: :object, properties: { acting_user_id: acting_user_id, **fields }, required: %w[title body] }
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

      response '403', 'not a Regular or staff, or (bot) `feature_unavailable`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', invalid do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/codex/lore_entries/{id}' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    get 'Show a Lore Entry' do
      tags 'Club Codex'
      description "Members (any signed-in caller). #{gate}"
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }

      response '200', 'the Lore Entry' do
        schema one_entry
      end

      response '401', 'not signed in' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no such Lore Entry, or the Feature is hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Edit a Lore Entry' do
      tags 'Club Codex'
      description 'Its author, or a Moderator and above, for anyone\'s (403 "Only its author or a Moderator can ' \
                  'edit this."). A mentioned member gets no say. Only the fields given change; send ' \
                  '`occurred_on` and `date_precision` as null to remove the date. Mentions are pulled again ' \
                  "from a new `body`. #{refusal} #{gate}"
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

      response '403', 'not its author or a Moderator, or (bot) `feature_unavailable`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no such Lore Entry, or the Feature is hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', invalid do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a Lore Entry' do
      tags 'Club Codex'
      description 'Its author, or a Moderator and above, for anyone\'s (403 "Only its author or a Moderator can ' \
                  'delete this."). A hard delete: its mentions go with it, and the author isn\'t told. The bot ' \
                  "sends `acting_user_id` as a query parameter. #{refusal} #{gate}"
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

      response '403', 'not its author or a Moderator, or (bot) `feature_unavailable`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no such Lore Entry, or the Feature is hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '502', '`backblaze_request_failed`: storage refused to remove one of its images (ticket #410); ' \
                      'the entry is kept, so the delete can be retried' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
