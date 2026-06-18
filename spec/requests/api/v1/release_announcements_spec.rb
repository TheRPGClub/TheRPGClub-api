# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/release_announcements', type: :request do
  # Client-writable GamedbReleaseAnnouncement columns. The controller's
  # #writable_data strips the bot-managed delivery columns (`sent_at`,
  # `skipped_at`, `skip_reason`) — they are read-only and the skip columns are
  # set only via the dedicated skip action.
  writable = {
    release_id: { type: :integer, description: 'The release to announce (gamedb_releases.release_id; also the PK). Required on create.' },
    announce_at: { type: :string, format: 'date-time', description: 'When to announce. Required on create; move it to reschedule.' }
  }

  path '/api/v1/games/{id}/release_announcements' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbGame game_id.'

    get "List a game's scheduled release announcements" do
      tags 'Release Announcements'
      description 'The scheduled announcements for the game\'s releases, ordered by `announce_at`. ' \
                  'Each row is keyed by `release_id` (1:1 with a release). The delivery columns ' \
                  '(`sent_at`, `skipped_at`, `skip_reason`) are bot-managed and read-only.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'release announcements list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/ReleaseAnnouncement' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Bulk-sync a game\'s release announcement schedule' do
      tags 'Release Announcements'
      description 'Admin/service-only bulk upsert of the game\'s announcement schedule (the bot\'s ' \
                  '`syncReleaseAnnouncements`). The body carries the computed pairs as an array under `data`. ' \
                  'Each pair is upserted by `release_id`: a new row is created, an existing one is moved only ' \
                  'when `announce_at` changes. Rows the bot\'s send loop already owns (`sent_at` or ' \
                  '`skipped_at` set) are never touched, and pairs whose `release_id` doesn\'t belong to the ' \
                  'game (or that omit `announce_at`) are ignored. Returns counts of rows written vs left as-is.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :array,
            items: {
              type: :object,
              properties: {
                release_id: { type: :integer, description: 'The release to (re)schedule (gamedb_releases.release_id).' },
                announce_at: { type: :string, format: 'date-time', description: 'When to announce it.' }
              },
              required: %w[release_id announce_at]
            }
          }
        },
        required: %w[data]
      }

      response '200', 'schedule synced' do
        schema type: :object, properties: {
          data: {
            type: :object,
            properties: {
              synced: { type: :integer, description: 'Rows created or moved.' },
              skipped: { type: :integer, description: 'Rows left as-is (already sent/skipped, unchanged, or not this game\'s).' }
            },
            required: %w[synced skipped]
          }
        }
      end

      response '403', 'forbidden — caller is not an admin or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/release_announcements' do
    post 'Schedule a release announcement' do
      tags 'Release Announcements'
      description 'Admin/service-only. Schedules the bot to announce a release. The body carries ' \
                  '`release_id` (the primary key, 1:1 with the release) and `announce_at`. The ' \
                  'delivery columns (`sent_at`, `skipped_at`, `skip_reason`) are bot-managed and ' \
                  'ignored on write — use the skip action to skip an announcement.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[release_id announce_at] } },
        required: %w[data]
      }

      response '201', 'announcement scheduled' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/ReleaseAnnouncement' } }
      end

      response '403', 'forbidden — caller is not an admin or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed (missing `announce_at` or unknown `release_id`)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing `data` parameter' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/release_announcements/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'GamedbReleaseAnnouncement release_id.'

    get 'Show a scheduled release announcement' do
      tags 'Release Announcements'
      produces 'application/json'

      response '200', 'announcement detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/ReleaseAnnouncement' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Reschedule a release announcement' do
      tags 'Release Announcements'
      description 'Admin/service-only. Reschedule a pending announcement by moving `announce_at`. ' \
                  'The bot-managed delivery columns are read-only and ignored on write.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/ReleaseAnnouncement' } }
      end

      response '403', 'forbidden — caller is not an admin or service' do
        schema '$ref' => '#/components/schemas/Error'
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

    put 'Replace a release announcement (alias)' do
      tags 'Release Announcements'
      description 'Admin/service-only. Alias for PATCH.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/ReleaseAnnouncement' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a release announcement' do
      tags 'Release Announcements'
      description 'Admin/service-only. Removes the scheduled announcement entirely.'
      produces 'application/json'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedResponse'
      end

      response '403', 'forbidden — caller is not an admin or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/release_announcements/{id}/skip' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'GamedbReleaseAnnouncement release_id.'

    post 'Skip a release announcement' do
      tags 'Release Announcements'
      description 'Admin/service-only. Marks the announcement skipped so the bot won\'t send it: ' \
                  'stamps `skipped_at` now and stores the optional `skip_reason`. The body is optional.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: false, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: { skip_reason: { type: :string, maxLength: 80 } }
          }
        }
      }

      response '200', 'skipped' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/ReleaseAnnouncement' } }
      end

      response '403', 'forbidden — caller is not an admin or service' do
        schema '$ref' => '#/components/schemas/Error'
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
