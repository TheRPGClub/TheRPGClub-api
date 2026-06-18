# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/release_announcements', type: :request do
  # Create body: a release to schedule plus its announce time.
  create_writable = {
    release_id: { type: :integer, description: 'The release to announce (gamedb_releases.release_id; also the PK). Required on create.' },
    announce_at: { type: :string, format: 'date-time', description: 'When to announce. Required on create.' }
  }

  # Update body: reschedule and/or set delivery state. The bot PATCHes `sent_at`
  # to mark an announcement sent, or `skipped_at` + `skip_reason` to mark it
  # missed (#109); all are optional and admin/service-gated.
  update_writable = {
    announce_at: { type: :string, format: 'date-time', description: 'Move the scheduled announce time.' },
    sent_at: { type: :string, format: 'date-time', description: 'Mark the announcement sent (set by the bot after posting).' },
    skipped_at: { type: :string, format: 'date-time', description: 'Mark the announcement missed/skipped.' },
    skip_reason: { type: :string, maxLength: 80, description: 'Why it was skipped (e.g. `release-window-missed`).' }
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
      description 'Admin/service-only. Rebuilds the game\'s announcement schedule from its releases and ' \
                  'applies canonicality (the bot\'s `syncReleaseAnnouncements` + `markNonCanonicalAnnouncements`). ' \
                  'Server-side and body-less — everything is computed from `gamedb_releases`. In one transaction ' \
                  'it (1) upserts an announcement for every release with a `release_date`, scheduling ' \
                  '`announce_at = release_date - 7 days` (a pending row is moved only when its time changes; rows ' \
                  'already sent/skipped are left alone); (2) clears the canonicality skip on rows that no longer ' \
                  'qualify as port-only / same-day-duplicate; and (3) skips rows that are now non-canonical ' \
                  '(`port-only-release` for a later release date, `same-day-platform-duplicate` for a same-day tie).'
      produces 'application/json'

      response '200', 'schedule synced' do
        schema type: :object, properties: {
          data: {
            type: :object,
            properties: {
              upserted: { type: :integer, description: 'Announcements inserted or moved.' },
              restored: { type: :integer, description: 'Rows whose canonicality skip was cleared.' },
              skipped: { type: :integer, description: 'Rows newly marked non-canonical (skipped).' }
            },
            required: %w[upserted restored skipped]
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

    put 'Bulk-sync a game\'s release announcement schedule (alias)' do
      tags 'Release Announcements'
      description 'Admin/service-only. Alias for PATCH.'
      produces 'application/json'

      response '200', 'schedule synced' do
        schema type: :object, properties: {
          data: {
            type: :object,
            properties: {
              upserted: { type: :integer },
              restored: { type: :integer },
              skipped: { type: :integer }
            },
            required: %w[upserted restored skipped]
          }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/release_announcements/due' do
    get 'List release announcements that are due to post' do
      tags 'Release Announcements'
      description 'Service-only poll feed (the bot\'s `listDueAnnouncements`). Returns the announcements ready ' \
                  'to post: not yet sent or skipped, whose `announce_at` has passed, whose release is still in ' \
                  'the future, and which are the canonical release for their game (earliest release date; on a ' \
                  'same-day tie the lowest `release_id`). Any pending announcement whose window has already ' \
                  'passed (its release has shipped) is marked skipped (`release-window-missed`) server-side ' \
                  'first, so it never appears here. Unpaginated; bounded by `limit`.'
      produces 'application/json'
      parameter name: :limit, in: :query, required: false,
                schema: { type: :integer, default: 25, minimum: 1, maximum: 100 },
                description: 'Max rows to return (default 25, clamped to 100).'

      response '200', 'due announcements' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/DueReleaseAnnouncement' } }
        }, required: %w[data]
      end

      response '403', 'forbidden — caller is not a service' do
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
                  '`release_id` (the primary key, 1:1 with the release) and `announce_at`. Delivery ' \
                  'state is set later via PATCH (`sent_at`, or `skipped_at` + `skip_reason`).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: create_writable, required: %w[release_id announce_at] } },
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

    patch 'Reschedule or mark a release announcement' do
      tags 'Release Announcements'
      description 'Admin/service-only. Move `announce_at`, and/or set delivery state: the bot PATCHes ' \
                  '`sent_at` to mark an announcement sent, or `skipped_at` + `skip_reason` to mark it missed.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: update_writable } },
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
        properties: { data: { type: :object, properties: update_writable } }
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
