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
                       description: "Author's display name. Service only; a member's comes from their record." },
    where: { type: :string, enum: RpgClubFeedback::WHERES, nullable: true,
             description: 'Bug Reports: where it happened. Required for a Bug Report.' },
    what_happened: { type: :string, nullable: true, maxLength: 2000,
                     description: 'Bug Reports: what happened. Required for a Bug Report.' },
    expected: { type: :string, nullable: true, maxLength: 2000,
                description: 'Bug Reports: what the member expected. Required for a Bug Report.' },
    steps: { type: :string, nullable: true, maxLength: 2000, description: 'Bug Reports: steps to reproduce (optional).' }
  }
  # What the author may change while Pending (PATCH); bug fields only on a Bug Report.
  editable = writable.slice(:title, :details, :where, :what_happened, :expected, :steps)
  # Status and the review columns are server-managed and ignored on create.

  path '/api/v1/feedback' do
    get 'List Feedback' do
      tags 'Feedback'
      description 'Open to any authenticated caller. The Feedback Board shows one kind at a time (`kind`) with an ' \
                  'Open / Closed filter (`status=open|closed`); `meta.totals` counts each kind\'s Open, Closed ' \
                  'and Done Feedback, whatever the filters, for the tabs. ' \
                  'By default (`sort=board`) Approved (not Done) first, then Pending, then Done, then ' \
                  'Rejected, Duplicate and Withdrawn; most upvoted first, then newest, within each; ' \
                  '`sort=recent` lists the latest activity first (`last_activity_at`, then newest ' \
                  'feedback_id), for the Feedback Board Dashboard Panel. Each row carries ' \
                  '`upvote_count`, `viewer_upvoted` (always false for the service) and `last_activity_at`.'
      produces 'application/json'
      parameter name: :kind, in: :query, schema: { type: :string }, required: false,
        description: 'Comma-separated kinds to include (feature_request, suggestion, bug_report). Absent = every kind.'
      parameter name: :status, in: :query, schema: { type: :string }, required: false,
        description: 'Comma-separated, combined with OR: `open` (pending and approved, Done included), ' \
                     '`closed` (rejected, duplicate, withdrawn), `done` (approved and Done), or single statuses ' \
                     '(pending, approved, rejected, withdrawn, duplicate). Absent = every status.'
      parameter name: :sort, in: :query, schema: { type: :string, enum: %w[board recent], default: 'board' },
        required: false,
        description: '`board`: Approved (not Done), Pending, Done, then closed; most upvoted, then newest, ' \
                     'within each. `recent`: latest activity first.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'Feedback list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Feedback' } },
          meta: { allOf: [ { '$ref' => '#/components/schemas/PaginationMeta' }, { type: :object, properties: {
            totals: { '$ref' => '#/components/schemas/FeedbackBoardTotals' }
          }, required: %w[totals] } ] }
        }
      end

      response '400', 'unknown status or kind' do
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
      description 'Members role holders, Moderator and above, or the service. `kind` and `title` are required; a Bug Report also needs `where`, `what_happened` and `expected`. ' \
                  'The bug fields (`where`, `what_happened`, `expected`, `steps`) are dropped for the other kinds; ' \
                  'a screenshot is added afterwards with `PUT /api/v1/feedback/{id}/screenshot`. ' \
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

      response '422', 'validation failed (e.g. missing or unknown kind, or a Bug Report without what happened or expected)' do
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

    patch 'Edit own Pending Feedback' do
      tags 'Feedback'
      description 'The author only, while Pending (staff and the service are refused). Changes `title`, ' \
                  '`details` and, on a Bug Report, `where`, `what_happened`, `expected` and `steps`; other fields, ' \
                  'and bug fields on the other kinds, are ignored. A Bug Report must keep `what_happened` and ' \
                  '`expected`. The screenshot has its own endpoint.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: editable } },
        required: %w[data]
      }

      response '200', 'edited' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Feedback' } }
      end

      response '422', 'validation failed (e.g. blank title, or a Bug Report without what happened or expected)' do
        schema '$ref' => '#/components/schemas/Error'
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

      response '400', 'missing data envelope' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/feedback/{feedback_id}/screenshot' do
    parameter name: :feedback_id, in: :path, schema: { type: :string }, required: true,
      description: 'RpgClubFeedback id (a Bug Report).'
    storage = 'Files are kept in the Backblaze bucket the GameDB game images use: 422 `backblaze_not_configured` ' \
              'when it is not set up, 502 `backblaze_request_failed` when Backblaze refuses an upload (nothing ' \
              'is changed).'

    put 'Add or replace a Bug Report screenshot' do
      tags 'Feedback'
      description 'The author only, while Pending; Bug Reports only (one screenshot each). Replaces any earlier ' \
                  'screenshot, whose file is removed. The type is told by the file\'s bytes. Send ' \
                  "`multipart/form-data`. Returns the Feedback with its `screenshot_url`. #{storage}"
      consumes 'multipart/form-data'
      produces 'application/json'
      parameter name: :data, in: :formData, required: true, schema: {
        type: :object,
        properties: {
          'data[file]' => { type: :string, format: :binary, description: 'PNG, JPEG or WebP, at most 5 MB.' }
        },
        required: [ 'data[file]' ]
      }

      response '200', 'stored' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Feedback' } }
      end

      response '422', '`invalid_image` (no file, not PNG/JPEG/WebP, empty or over 5 MB), `screenshot_not_allowed` ' \
                      '(not a Bug Report) or `backblaze_not_configured`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'not pending' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found, or the Feature is hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not the author' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '502', '`backblaze_request_failed`: nothing was changed' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Remove a Bug Report screenshot' do
      tags 'Feedback'
      description 'The author only, while Pending. A no-op without a screenshot. The file is removed after the ' \
                  'screenshot is cleared; a storage failure only leaves the file behind.'
      produces 'application/json'

      response '200', 'removed; returns the Feedback' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Feedback' } }
      end

      response '409', 'not pending' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found, or the Feature is hidden from the caller' do
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

  path '/api/v1/feedback/{id}/approve' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubFeedback id.'

    post 'Approve Feedback into a GitHub issue' do
      tags 'Feedback'
      description 'Superadmin or the service, while Pending. Opens a GitHub issue in `target_repo` (title = the ' \
                  'Feedback title, body = "<author name>: <details>" plus a hidden Feedback marker, label = the ' \
                  'kind\'s label in that repo; a Bug Report\'s body instead lays out where, what happened, expected, ' \
                  'steps and details, and links the Feedback on the Feedback Board (never the screenshot: the repos ' \
                  'are public)) through the GitHub App, stores its number and URL, and sets ' \
                  'status approved. The board link is the origin of DISCORD_OAUTH_SUCCESS_REDIRECT; unset, it is ' \
                  'named without a link. ' \
                  'An issue that already carries the marker (an earlier attempt whose response ' \
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

  path '/api/v1/feedback/{id}/duplicate' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubFeedback id.'

    post 'Mark Feedback a Duplicate' do
      tags 'Feedback'
      description 'Superadmin or the service, while Pending (Approved Feedback is refused: close its GitHub issue ' \
                  'instead). Sets status duplicate with `duplicate_of_id` = the original, resolved to its root when ' \
                  'it is itself a Duplicate. The original may be of any kind and must be Pending or Approved (Done ' \
                  'included), not Rejected or Withdrawn. The upvotes move to the original, each member counted once, ' \
                  'and Duplicates of this Feedback are repointed to the original. ' \
                  'Enqueues a `feedback_outcome` bot job (payload as for reject, plus `duplicate_of_id` and ' \
                  '`duplicate_of_title`); `meta.outcome_job_id` is that job.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              original_id: { type: :integer, description: 'The Feedback this one duplicates.' },
              reviewed_by: { type: :string, description: 'Service only: the Discord id of the reviewer. A signed-in Superadmin is always the reviewer.' }
            },
            required: %w[original_id]
          }
        },
        required: %w[data]
      }

      response '200', 'marked a Duplicate' do
        schema type: :object, properties: {
          data: { '$ref' => '#/components/schemas/Feedback' },
          meta: { '$ref' => '#/components/schemas/FeedbackReviewMeta' }
        }
      end

      response '422', 'original missing, unknown, this Feedback itself, or Rejected/Withdrawn' do
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

  path '/api/v1/feedback/{id}/kind' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubFeedback id.'

    post 'Change the kind of Feedback' do
      tags 'Feedback'
      description 'Superadmin or the service, while Pending. Sets `kind`; a kind\'s required fields (a Bug ' \
                  'Report\'s) are not checked, since staff are reshaping the Feedback, not filing it. Enqueues nothing.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: { kind: { type: :string, enum: RpgClubFeedback::KINDS } },
            required: %w[kind]
          }
        },
        required: %w[data]
      }

      response '200', 'kind changed' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Feedback' } }
      end

      response '422', 'kind missing or unknown' do
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
                  'Only Pending and Approved Feedback that is not Done takes upvotes.'
      produces 'application/json'

      response '200', 'upvoted; returns the updated Feedback' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Feedback' } }
      end

      response '409', 'upvotes frozen: Done, Rejected, Withdrawn or a Duplicate' do
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
      description "Members role holders or staff, signed in (the service is refused). Removes the caller's upvote if any (a no-op otherwise). " \
                  'Upvotes are frozen as for upvoting: refused unless Pending, or Approved and not Done.'
      produces 'application/json'

      response '200', 'removed; returns the updated Feedback' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Feedback' } }
      end

      response '409', 'upvotes frozen: Done, Rejected, Withdrawn or a Duplicate' do
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
  end
end
