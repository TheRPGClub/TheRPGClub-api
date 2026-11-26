# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/patches', type: :request do
  fields = {
    title: { type: :string, nullable: true, maxLength: Patch::TITLE_MAX, description: 'Optional.' },
    rich_body: { type: :array, items: { type: :object, additionalProperties: true },
                 description: 'The Patch as Plate.js content, stored as given.' },
    body: { type: :string, description: 'The full text as Discord markdown, made from `rich_body`.' },
    cut_body: { type: :string, description: '`body` cut to Discord\'s limit, ending in "..." when cut.' }
  }
  writers = 'Admins and Superadmins signed in on the website only: Moderators, members and the service token get ' \
            '403 `forbidden` ("Only Admins can write Patches.").'
  gate = 'Belongs to the Patch Notes Feature: not found for non-staff in Preview and for everyone when Off.'
  public_gate = 'Public: no sign-in needed. A signed-out caller is treated like any non-staff member, so Patches ' \
                'are found only while Patch Notes is Live (not found in Preview and Off).'
  one_patch = { type: :object, properties: { data: { '$ref' => '#/components/schemas/Patch' } } }
  invalid = 'invalid_patch: a field a Patch does not take, `title` that is not text or null, `body` or ' \
            '`cut_body` that is not text, `rich_body` that is not a list, or a NUL character'

  path '/api/v1/patches' do
    get 'List Patches' do
      tags 'Patch Notes'
      description "Newest first. Published Patches only, unless an Admin or Superadmin asks for `draft` or `all`. #{public_gate}"
      produces 'application/json'
      security [ {}, { bearerAuth: [] } ]
      parameter name: :status, in: :query, required: false,
        schema: { type: :string, enum: Api::V1::PatchesController::STATUS_FILTERS, default: 'published' },
        description: '`draft` and `all` are for Admins and Superadmins (anyone else gets 403).'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'Patches' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Patch' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '400', 'invalid_status: `status` is not published, draft or all' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', '`draft` or `all` asked by someone who is not an Admin or Superadmin' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the Feature is Off, or Preview and the caller is not an Admin or Superadmin' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Start a Patch' do
      tags 'Patch Notes'
      description "A new draft, numbered from the Patch sequence. #{writers} #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object, properties: { data: { type: :object, properties: fields } }, required: %w[data]
      }

      response '201', 'started' do
        schema one_patch
      end

      response '400', 'missing `data`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'not signed in' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not an Admin or Superadmin, or the service token' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', invalid do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/patches/{number}' do
    parameter name: :number, in: :path, schema: { type: :integer }, required: true

    get 'Show a Patch' do
      tags 'Patch Notes'
      description "A published Patch, with the published Patches either side of it. Admins and Superadmins also " \
                  "find drafts. #{public_gate}"
      produces 'application/json'
      security [ {}, { bearerAuth: [] } ]

      response '200', 'the Patch' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/PatchWithNeighbours' } }
      end

      response '404', 'no such published Patch, or the Feature is hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Edit a Patch' do
      tags 'Patch Notes'
      description "Changes only the fields given, draft or published. #{writers} #{gate}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object, properties: { data: { type: :object, properties: fields } }, required: %w[data]
      }

      response '200', 'edited' do
        schema one_patch
      end

      response '401', 'not signed in' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not an Admin or Superadmin, or the service token' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no such Patch, or the Feature is Off' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', invalid do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a draft Patch' do
      tags 'Patch Notes'
      description "Drafts only; its number is never used again. #{writers} #{gate}"
      produces 'application/json'

      response '200', 'deleted' do
        schema type: :object, properties: {
          data: { type: :object, properties: { number: { type: :integer }, deleted: { type: :boolean } },
                  required: %w[number deleted] }
        }
      end

      response '401', 'not signed in' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not an Admin or Superadmin, or the service token' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no such Patch, or the Feature is Off' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'published: unpublish the Patch first' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/patches/{number}/publish' do
    parameter name: :number, in: :path, schema: { type: :integer }, required: true

    post 'Publish a Patch' do
      tags 'Patch Notes'
      description "Puts a draft on the website (only; posting to Discord is a separate step) and stamps " \
                  "`published_at`. Never blocked by length. #{writers} #{gate}"
      produces 'application/json'

      response '200', 'published' do
        schema one_patch
      end

      response '401', 'not signed in' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not an Admin or Superadmin, or the service token' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no such Patch, or the Feature is Off' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'already_published' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/patches/{number}/unpublish' do
    parameter name: :number, in: :path, schema: { type: :integer }, required: true

    post 'Unpublish a Patch' do
      tags 'Patch Notes'
      description "Takes a published Patch back to a draft, hidden from every read but staff's; it keeps its " \
                  "number. #{writers} #{gate}"
      produces 'application/json'

      response '200', 'unpublished' do
        schema one_patch
      end

      response '401', 'not signed in' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not an Admin or Superadmin, or the service token' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no such Patch, or the Feature is Off' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'not_published' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
