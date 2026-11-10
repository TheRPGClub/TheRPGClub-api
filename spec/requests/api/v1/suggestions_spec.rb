# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/suggestions', type: :request do
  # The client-writable RpgClubSuggestion columns. `suggestion_id` and the
  # timestamps are server-managed.
  writable = {
    title: { type: :string, description: 'Suggestion title. Required on create.' },
    details: { type: :string, nullable: true, description: 'Optional longer description.' },
    labels: { type: :string, nullable: true, description: 'Optional labels (free-form string).' },
    created_by: { type: :string, nullable: true,
                  description: 'Discord user id of the author. Service only; a member is always the author.' },
    created_by_name: { type: :string, nullable: true,
                       description: "Author's display name. Service only; a member's comes from their record." }
  }
  # Status and the review columns are server-managed and ignored on create.

  path '/api/v1/suggestions' do
    get 'List suggestions' do
      tags 'Suggestions'
      description 'Open to any authenticated caller. Most upvoted first, then newest. Each row carries ' \
                  '`upvote_count` and `viewer_upvoted` (always false for the service).'
      produces 'application/json'
      parameter name: :status, in: :query, schema: { type: :string }, required: false,
        description: 'Comma-separated statuses to include (pending, approved, rejected, withdrawn). ' \
                     'Absent = every status. The Suggestion Board default is `pending,approved`.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'suggestions list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Suggestion' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '400', 'unknown status' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a suggestion' do
      tags 'Suggestions'
      description 'Members role holders, Moderator and above, or the service. `title` is required; everything else is optional. ' \
                  'Always created Pending. A member is recorded as the author (body `created_by` and ' \
                  '`created_by_name` are ignored) and their submission enqueues a `suggestion_submitted` ' \
                  'bot job (payload `{ suggestion_id, created_by, feature_key: "suggestions" }`) so the bot pings the bot dev. ' \
                  "A service create enqueues nothing: the bot pings inline for its own submissions."
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[title] } },
        required: %w[data]
      }

      response '201', 'suggestion created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Suggestion' } }
      end

      response '422', 'validation failed' do
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

  path '/api/v1/suggestions/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubSuggestion id.'

    get 'Show a suggestion' do
      tags 'Suggestions'
      produces 'application/json'

      response '200', 'suggestion detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Suggestion' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/suggestions/{id}/approve' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubSuggestion id.'

    post 'Approve a suggestion into a GitHub issue' do
      tags 'Suggestions'
      description 'Superadmin or the service, while Pending. Opens a GitHub issue in `target_repo` (title = the ' \
                  'Suggestion title, body = "<author name>: <details>" plus a hidden Suggestion marker, labels = ' \
                  'the comma-separated `labels`) through the GitHub App, stores its number and URL, and sets ' \
                  'status approved. An issue that already carries the marker (an earlier attempt whose response ' \
                  'was lost) is reused instead of opening a duplicate. ' \
                  'Enqueues a `suggestion_outcome` bot job (payload `{ suggestion_id, outcome, created_by, title, ' \
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
              target_repo: { type: :string, enum: RpgClubSuggestion::TARGET_REPOS },
              reviewed_by: { type: :string, description: 'Service only: the Discord id of the reviewer. A signed-in Superadmin is always the reviewer.' }
            },
            required: %w[target_repo]
          }
        },
        required: %w[data]
      }

      response '200', 'approved' do
        schema type: :object, properties: {
          data: { '$ref' => '#/components/schemas/Suggestion' },
          meta: { '$ref' => '#/components/schemas/SuggestionReviewMeta' }
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

  path '/api/v1/suggestions/{id}/reject' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubSuggestion id.'

    post 'Reject a suggestion' do
      tags 'Suggestions'
      description 'Superadmin or the service, while Pending. Sets status rejected with the (trimmed) reason. ' \
                  'Enqueues a `suggestion_outcome` bot job (payload `{ suggestion_id, outcome, created_by, title, ' \
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
          data: { '$ref' => '#/components/schemas/Suggestion' },
          meta: { '$ref' => '#/components/schemas/SuggestionReviewMeta' }
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

  path '/api/v1/suggestions/{id}/withdraw' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubSuggestion id.'

    post 'Withdraw a suggestion' do
      tags 'Suggestions'
      description 'The author only, while Pending. Staff and the service are refused.'
      produces 'application/json'

      response '200', 'withdrawn' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Suggestion' } }
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

  path '/api/v1/suggestions/{id}/upvote' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubSuggestion id.'

    post 'Upvote a suggestion' do
      tags 'Suggestions'
      description 'Members role holders or staff, signed in (the service is refused). One upvote per member; repeating it is a no-op. ' \
                  'Only Pending and Approved suggestions take upvotes.'
      produces 'application/json'

      response '200', 'upvoted; returns the updated suggestion' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Suggestion' } }
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
      tags 'Suggestions'
      description "Members role holders or staff, signed in (the service is refused). Removes the caller's upvote if any (a no-op otherwise), whatever the status."
      produces 'application/json'

      response '200', 'removed; returns the updated suggestion' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Suggestion' } }
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
