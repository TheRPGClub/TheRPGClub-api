# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/challenge_runs', type: :request do
  run_list = {
    type: :object, properties: {
      data: { type: :array, items: { '$ref' => '#/components/schemas/ChallengeRun' } },
      meta: { '$ref' => '#/components/schemas/PaginationMeta' }
    }
  }
  one_run = { type: :object, properties: { data: { '$ref' => '#/components/schemas/ChallengeRun' } } }
  progress = 'Progress fills in by itself from the member\'s Game Completions and Now Playing: a Pool game in Now ' \
             'Playing is In Progress, and a Game Completion dated inside the Run\'s window Clears it. Finished is ' \
             'final.'
  hidden = 'Runs of a hidden Challenge are listed only for Moderators and above, its Host and the Run\'s member.'
  status_filter = { type: :string, enum: ChallengeRun::STATUSES }

  path '/api/v1/users/{user_id}/challenge_runs' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get "List a member's Runs" do
      tags 'Challenges'
      description "Members (the `challenges` Feature). The member's Runs, current and past, newest first, for " \
                  "their profile. #{progress} #{hidden} The bot may name the member it reads for with " \
                  '`acting_user_id`.'
      produces 'application/json'
      parameter name: :status, in: :query, required: false, schema: status_filter
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'Runs' do
        schema run_list
      end

      response '400', 'an unknown `status`' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/challenges/{challenge_id}/runs' do
    parameter name: :challenge_id, in: :path, schema: { type: :integer }, required: true

    get "List a Challenge's Runs" do
      tags 'Challenges'
      description "Members. Newest first, with progress. 404 for a Challenge hidden from the caller. #{hidden}"
      produces 'application/json'
      parameter name: :status, in: :query, required: false, schema: status_filter
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'Runs' do
        schema run_list
      end

      response '404', 'not found, or hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Start a Run' do
      tags 'Challenges'
      description 'Starts the acting member\'s Run of an Open Challenge. A Seasonal Run belongs to the Season it ' \
                  'starts in and counts play from earlier in that Season, so it may Finish at once (queuing a ' \
                  '`challenge_announce` `run_finished` job). An Always Open Run counts play from its start day. ' \
                  'Refusals carry `{ error, message }` written for members: 409 `challenge_closed`, and 409 ' \
                  '`run_active` (with `run_id`) when the member already has an Active Run of it. The bot sends ' \
                  '`{ "data": { "acting_user_id": "..." } }` (400 without; 403 `feature_unavailable` when the ' \
                  'Feature Flag hides the Feature from that member).'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: false, schema: {
        type: :object, properties: { data: { type: :object, properties: { acting_user_id: { type: :string } } } }
      }

      response '201', 'the new Run' do
        schema one_run
      end

      response '404', 'not found, or hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'challenge_closed or run_active' do
        schema type: :object, properties: {
          error: { type: :string, enum: %w[challenge_closed run_active] }, message: { type: :string },
          run_id: { type: :integer, description: 'run_active only: the member\'s Active Run.' }
        }
      end
    end
  end

  path '/api/v1/challenge_runs/{id}' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    get 'Show a Run' do
      tags 'Challenges'
      description "Members. #{progress} #{hidden}"
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }

      response '200', 'the Run' do
        schema one_run
      end

      response '404', 'not found, or hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a Run' do
      tags 'Challenges'
      description 'The Run\'s member only (403 otherwise): a Finished, Expired or Abandoned Run. An Active Run ' \
                  'is 409 `run_active` until abandoned. The bot sends `acting_user_id` as a query parameter.'
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }

      response '200', 'deleted' do
        schema type: :object, properties: {
          data: { type: :object, properties: { id: { type: :integer }, deleted: { type: :boolean } } }
        }
      end

      response '403', 'not the Run\'s member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'run_active' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/challenge_runs/{id}/abandon' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    post 'Abandon a Run' do
      tags 'Challenges'
      description 'The Run\'s member only (403 otherwise). The Run stays on their profile, Abandoned, until they ' \
                  'delete it. 409 `run_not_active` unless it is Active. The bot sends ' \
                  '`{ "data": { "acting_user_id": "..." } }`.'
      produces 'application/json'

      response '200', 'the Abandoned Run' do
        schema one_run
      end

      response '403', 'not the Run\'s member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'run_not_active' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
