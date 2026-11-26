# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/pending_changes', type: :request do
  staff = 'Admins and Superadmins signed in on the website only: Moderators, members and the service token get ' \
          '403 `forbidden`. Belongs to the Patch Notes Feature: not found for everyone when Off.'
  one_change = { type: :object, properties: { data: { '$ref' => '#/components/schemas/PendingChange' } } }
  some_changes = { type: :object, properties: { data: { type: :array, items: { '$ref' => '#/components/schemas/PendingChange' } } } }
  error = { '$ref' => '#/components/schemas/Error' }

  path '/api/v1/pending_changes' do
    get 'List Pending Changes' do
      tags 'Patch Notes'
      description "Newest first. #{staff}"
      produces 'application/json'
      parameter name: :status, in: :query, required: false,
        schema: { type: :string, enum: Api::V1::PendingChangesController::STATUS_FILTERS, default: 'open' }
      parameter name: :patch, in: :query, required: false, schema: { type: :integer },
        description: 'Only the ones this Patch number covers.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'Pending Changes' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/PendingChange' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '400', 'invalid_status: `status` is not open, covered, dismissed or all' do
        schema error
      end

      response '401', 'not signed in' do
        schema error
      end

      response '403', 'not an Admin or Superadmin, or the service token' do
        schema error
      end

      response '404', 'the Feature is Off' do
        schema error
      end
    end

    post 'Report a Pending Change' do
      tags 'Patch Notes'
      description 'The versioning job reports a merged pull request, which also sets that repo\'s current version. ' \
                  'Only the release token (RPGCLUB_RELEASE_API_TOKEN) is accepted; it is accepted nowhere else. ' \
                  'Once per repo and pull request: a repeat returns the recorded one unchanged. Collects whatever ' \
                  'the Patch Notes Feature\'s state. Other keys in `data` are ignored.'
      consumes 'application/json'
      produces 'application/json'
      security [ { releaseToken: [] } ]
      parameter name: :body, in: :body, required: true, schema: {
        type: :object, required: %w[data], properties: {
          data: { type: :object, required: %w[repo pr_number type title version], properties: {
            repo: { type: :string, enum: PendingChange::REPOS },
            pr_number: { type: :integer, minimum: 1 },
            type: { type: :string, enum: PendingChange::TYPES, description: 'The pull request title\'s type.' },
            title: { type: :string, maxLength: PendingChange::TITLE_MAX },
            version: { type: :string, pattern: '^\d+\.\d+\.\d+$', description: 'The version this merge produced.' },
            patch_note: { type: :string, nullable: true, maxLength: PendingChange::PATCH_NOTE_MAX,
                          description: 'The pull request\'s optional "Patch note:" line.' }
          } }
        }
      }

      response '201', 'recorded' do
        schema one_change
      end

      response '200', 'already recorded for this repo and pull request; unchanged' do
        schema one_change
      end

      response '400', 'missing `data`' do
        schema error
      end

      response '401', 'no token, or an unknown one' do
        schema error
      end

      response '403', 'the bot\'s service token or a member\'s session' do
        schema error
      end

      response '422', 'invalid_pending_change: a missing field, an unknown repo or type, a version that is not ' \
                      'x.y.z, or a NUL character' do
        schema error
      end
    end
  end

  path '/api/v1/pending_changes/{id}/dismiss' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    post 'Dismiss a Pending Change' do
      tags 'Patch Notes'
      description "Members don't need to hear about it, so it leaves the drafts. #{staff}"
      produces 'application/json'

      response '200', 'dismissed' do
        schema one_change
      end

      response '403', 'not an Admin or Superadmin, or the service token' do
        schema error
      end

      response '404', 'no such Pending Change, or the Feature is Off' do
        schema error
      end

      response '422', 'already_dismissed, or covered (a Patch covers it)' do
        schema error
      end
    end
  end

  path '/api/v1/pending_changes/{id}/undismiss' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    post 'Undo a dismissal' do
      tags 'Patch Notes'
      description "Opens a dismissed Pending Change again. #{staff}"
      produces 'application/json'

      response '200', 'open again' do
        schema one_change
      end

      response '403', 'not an Admin or Superadmin, or the service token' do
        schema error
      end

      response '404', 'no such Pending Change, or the Feature is Off' do
        schema error
      end

      response '422', 'not_dismissed' do
        schema error
      end
    end
  end

  path '/api/v1/patches/{number}/pending_changes' do
    parameter name: :number, in: :path, schema: { type: :integer }, required: true

    put 'Set what a Patch covers' do
      tags 'Patch Notes'
      description 'Replaces the whole list: the ids given become covered by this Patch, and the ones it covered ' \
                  'before but are left out are open again. Refused whole, changing nothing. Draft or published. ' \
                  "Deleting a draft Patch opens what it covered. #{staff}"
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object, required: %w[data], properties: {
          data: { type: :object, required: %w[ids], properties: { ids: { type: :array, items: { type: :integer } } } }
        }
      }

      response '200', 'what the Patch now covers, newest first' do
        schema some_changes
      end

      response '403', 'not an Admin or Superadmin, or the service token' do
        schema error
      end

      response '404', 'no such Patch or Pending Change, or the Feature is Off' do
        schema error
      end

      response '422', 'invalid_pending_changes (ids is not a list of ids), dismissed (undo the dismissal first), ' \
                      'covered_elsewhere (another Patch covers one)' do
        schema error
      end
    end
  end

  path '/api/v1/versions' do
    get 'Current versions' do
      tags 'Patch Notes'
      description 'Each repo\'s current version, from its newest Pending Change; null until versioning reports ' \
                  'one. Public: no sign-in needed, whatever the Patch Notes Feature\'s state.'
      produces 'application/json'
      security [ {} ]

      response '200', 'the versions' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Versions' } }
      end
    end
  end
end
