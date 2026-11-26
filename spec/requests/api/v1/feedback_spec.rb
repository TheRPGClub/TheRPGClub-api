# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/feedback', type: :request do
  # The client-writable RpgClubFeedback columns. `feedback_id` and the
  # timestamps are server-managed.
  writable = {
    kind: { type: :string, enum: RpgClubFeedback::KINDS,
            description: 'Feature Request, Suggestion or Bug Report. Required on create.' },
    title: { type: :string, description: 'Title. Required on create.' },
    details: { type: :string, nullable: true, description: 'Optional longer description.' },
    created_by: { type: :string, nullable: true,
                  description: 'Discord user id of the author. Service only; a member is always the author.' },
    created_by_name: { type: :string, nullable: true,
                       description: "Author's display name. Service only; a member's comes from their record." }
  }
  # Status and the review columns are server-managed and ignored on create.

  path '/api/v1/feedback' do
    get 'List Feedback' do
      tags 'Feedback'
      description 'Open to any authenticated caller. By default (`sort=board`) most upvoted first, then ' \
                  'newest; `sort=recent` lists the latest activity first (`last_activity_at`, then newest ' \
                  'feedback_id), for the Feedback Board Dashboard Panel. Each row carries ' \
                  '`upvote_count`, `viewer_upvoted` (always false for the service) and `last_activity_at`.'
      produces 'application/json'
      parameter name: :status, in: :query, schema: { type: :string }, required: false,
        description: 'Comma-separated statuses to include (pending, approved, rejected, withdrawn). ' \
                     'Absent = every status. The Feedback Board default is `pending,approved`.'
      parameter name: :sort, in: :query, schema: { type: :string, enum: %w[board recent], default: 'board' },
        required: false,
        description: '`board`: most upvoted, then newest. `recent`: latest activity first.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'Feedback list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Feedback' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '400', 'unknown status' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'unknown sort (`invalid_sort`)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create Feedback' do
      tags 'Feedback'
      description 'Members role holders, Moderator and above, or the service. `kind` and `title` are required; everything else is optional. ' \
                  'Always created Pending. A member is recorded as the author (body `created_by` and ' \
                  '`created_by_name` are ignored) and their submission enqueues a `feedback_submitted` ' \
                  'bot job (payload `{ feedback_id, kind, created_by, feature_key: "feedback" }`) so the bot pings the bot dev. ' \
                  "A service create enqueues nothing: the bot pings inline for its own submissions."
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[kind title] } },
        required: %w[data]
      }

      response '201', 'Feedback created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Feedback' } }
      end

      response '422', 'validation failed (e.g. missing or unknown kind)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller lacks the Members role and is not staff' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing data envelope' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/feedback/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubFeedback id.'

    get 'Show Feedback' do
      tags 'Feedback'
      produces 'application/json'

      response '200', 'Feedback detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Feedback' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/feedback/{id}/approve' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubFeedback id.'

    post 'Approve Feedback into a GitHub issue' do
      tags 'Feedback'
      description 'Superadmin or the service, while Pending. Opens a GitHub issue in `target_repo` (title = the ' \
                  'Feedback title, body = "<author name>: <details>" plus a hidden Feedback marker, label = the ' \
                  'kind\'s label in that repo) through the GitHub App, stores its number and URL, and sets ' \
                  'status approved. An issue that already carries the marker (an earlier attempt whose response ' \
                  'was lost) is reused instead of opening a duplicate. ' \
                  'Enqueues a `feedback_outcome` bot job (payload `{ feedback_id, kind, outcome, created_by, title, ' \
                  'github_issue_number, github_issue_url, rejection_reason }`), the bot\'s own reviews included; ' \
                  '`meta.outcome_job_id` is that job, for polling `GET /api/v1/bot_jobs/{id}`.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              target_repo: { type: :string, enum: RpgClubFeedback::TARGET_REPOS },
              reviewed_by: { type: :string, description: 'Service only: the Discord id of the reviewer. A signed-in Superadmin is always the reviewer.' }
            },
            required: %w[target_repo]
          }
        },
        required: %w[data]
      }

      response '200', 'approved' do
        schema type: :object, properties: {
          data: { '$ref' => '#/components/schemas/Feedback' },
          meta: { '$ref' => '#/components/schemas/FeedbackReviewMeta' }
        }
      end

      response '422', 'target_repo missing or not in the allowlist' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '502', 'GitHub refused or failed (error github_issue_failed); nothing changed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '503', 'GitHub App not configured (error github_not_configured)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'not pending, or `approval_in_progress` while another approval is calling GitHub' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not a Superadmin or the service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing data envelope' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/feedback/{id}/reject' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubFeedback id.'

    post 'Reject Feedback' do
      tags 'Feedback'
      description 'Superadmin or the service, while Pending. Sets status rejected with the (trimmed) reason. ' \
                  'Enqueues a `feedback_outcome` bot job (payload `{ feedback_id, kind, outcome, created_by, title, ' \
                  'github_issue_number, github_issue_url, rejection_reason }`), the bot\'s own reviews included; ' \
                  '`meta.outcome_job_id` is that job, for polling `GET /api/v1/bot_jobs/{id}`.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              rejection_reason: { type: :string, maxLength: 2000 },
              reviewed_by: { type: :string, description: 'Service only: the Discord id of the reviewer. A signed-in Superadmin is always the reviewer.' }
            },
            required: %w[rejection_reason]
          }
        },
        required: %w[data]
      }

      response '200', 'rejected' do
        schema type: :object, properties: {
          data: { '$ref' => '#/components/schemas/Feedback' },
          meta: { '$ref' => '#/components/schemas/FeedbackReviewMeta' }
        }
      end

      response '422', 'blank or too long rejection_reason' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'not pending' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not a Superadmin or the service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing data envelope' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/feedback/{id}/withdraw' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubFeedback id.'

    post 'Withdraw Feedback' do
      tags 'Feedback'
      description 'The author only, while Pending. Staff and the service are refused.'
      produces 'application/json'

      response '200', 'withdrawn' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Feedback' } }
      end

      response '409', 'not pending' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not the author' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/feedback/{id}/upvote' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubFeedback id.'

    post 'Upvote Feedback' do
      tags 'Feedback'
      description 'Members role holders or staff, signed in (the service is refused). One upvote per member; repeating it is a no-op. ' \
                  'Only Pending and Approved Feedback takes upvotes.'
      produces 'application/json'

      response '200', 'upvoted; returns the updated Feedback' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Feedback' } }
      end

      response '409', 'rejected or withdrawn' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: not a Members role holder or staff, or the service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Remove an upvote' do
      tags 'Feedback'
      description "Members role holders or staff, signed in (the service is refused). Removes the caller's upvote if any (a no-op otherwise), whatever the status."
      produces 'application/json'

      response '200', 'removed; returns the updated Feedback' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Feedback' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: not a Members role holder or staff, or the service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
