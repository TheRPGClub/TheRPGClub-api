# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/challenge_runs', type: :request do
  run_list = {
    type: :object, properties: {
      data: { type: :array, items: { '$ref' => '#/components/schemas/ChallengeRun' } },
      meta: { '$ref' => '#/components/schemas/PaginationMeta' }
    }
  }
  member_run_list = {
    type: :object, properties: {
      data: { type: :array, items: { '$ref' => '#/components/schemas/ChallengeRun' } },
      meta: { allOf: [ { '$ref' => '#/components/schemas/PaginationMeta' }, { type: :object, properties: {
        signups: { type: :array, items: { '$ref' => '#/components/schemas/ChallengeOpenSignup' },
                   description: "The member's Secret Santa sign-ups that have no Run yet (their Edition is still " \
                                'in sign-up), soonest draw first, whatever `status` asks for.' }
      } } ] }
    }
  }
  one_run = { type: :object, properties: { data: { '$ref' => '#/components/schemas/ChallengeRun' } } }
  started_run = {
    type: :object, properties: {
      data: { '$ref' => '#/components/schemas/ChallengeRun' },
      meta: { type: :object, properties: {
        notices: { type: :array, description: 'What the member should know about the new Run.', items: {
          type: :object, properties: {
            code: { type: :string, enum: %w[birth_year_shown] }, message: { type: :string }
          }
        } }
      } }
    }
  }
  progress = 'Progress fills in by itself from the member\'s Game Completions and Now Playing: a Pool game in Now ' \
             'Playing is In Progress, and a Game Completion dated inside the Run\'s window Clears it. A Slots Run\'s ' \
             'Cleared game fills the earliest open year it was released in (anywhere), one slot per game; a range ' \
             'ending at the current year is Caught Up while every year so far is Cleared. Earlier play counts only ' \
             'when picked by hand (Counts past play). Finished is final.'
  hidden = 'Runs of a hidden Challenge are listed only for Moderators and above, its Host and the Run\'s member.'
  status_filter = { type: :string, enum: ChallengeRun::STATUSES + %w[ended],
                    description: '`ended`: Finished, Expired and Abandoned.' }

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
        schema member_run_list
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
                  '`run_active` (with `run_id`) when the member already has an Active Run of it. A member has at ' \
                  'most one Run of a Seasonal Challenge per Season, whatever its status: 409 `season_run_exists` ' \
                  '(with `run_id`) until the next Season. A Slots Run copies ' \
                  'its first year: a birth-year one is 409 `birth_date_required` without a Birth Date or with one ' \
                  'that has no year, and 422 ' \
                  '`no_slots` when the birth year comes after the last year, and `meta.notices` tells the member ' \
                  'their birth year shows on the Run. An Assignment (Secret Santa) Challenge is 409 ' \
                  '`signup_required`: its Runs come from an Edition\'s draw. The bot sends ' \
                  '`{ "data": { "acting_user_id": "..." } }` (400 without; 403 `feature_unavailable` when the ' \
                  'Feature Flag hides the Feature from that member).'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: false, schema: {
        type: :object, properties: { data: { type: :object, properties: { acting_user_id: { type: :string } } } }
      }

      response '201', 'the new Run' do
        schema started_run
      end

      response '404', 'not found, or hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'challenge_closed, run_active, season_run_exists, birth_date_required or signup_required' do
        schema type: :object, properties: {
          error: { type: :string,
                   enum: %w[challenge_closed run_active season_run_exists birth_date_required signup_required] },
          message: { type: :string },
          run_id: { type: :integer,
                    description: 'run_active: the member\'s Active Run; season_run_exists: their Run in this Season.' }
        }
      end

      response '422', 'no_slots: a birth-year Slots Run whose birth year comes after the last year' do
        schema '$ref' => '#/components/schemas/Error'
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

  path '/api/v1/challenge_runs/{id}/slot_move' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    post 'Move a game to another year of a Slots Run' do
      tags 'Challenges'
      description 'The Run\'s member only (403 otherwise). Puts a game Cleared on the Active Slots Run in another ' \
                  'open year it was released in (anywhere); it keeps that slot while it still holds, and a Cleared ' \
                  'game waiting for its old year fills it. The bot adds `acting_user_id` to `data`.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object, required: %w[data], properties: {
          data: { type: :object, required: %w[game_id slot_year], properties: {
            game_id: { type: :integer }, slot_year: { type: :integer }, acting_user_id: { type: :string }
          } }
        }
      }

      response '200', 'the Run' do
        schema one_run
      end

      response '400', 'game_id or slot_year missing or not a whole number' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not the Run\'s member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'slot_filled (with the filling `game_id`) or run_not_active' do
        schema type: :object, properties: {
          error: { type: :string, enum: %w[slot_filled run_not_active] }, message: { type: :string },
          game_id: { type: :integer, description: 'slot_filled only: the game filling that year.' }
        }
      end

      response '422', 'not_slots, not_cleared, slot_out_of_range or slot_not_fitting' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/challenge_runs/{id}/past_pick' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    post 'Pick a past Game Completion for a slot' do
      tags 'Challenges'
      description 'The Run\'s member only (403 otherwise). With Counts past play on, puts one of the member\'s Game ' \
                  'Completions dated before the Active Slots Run started (or undated) in an open year its game was ' \
                  'released in. Earlier play counts only this way. The pick holds while its Game Completion ' \
                  'exists (a Finished Run keeps it regardless). The bot adds `acting_user_id` to `data`.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object, required: %w[data], properties: {
          data: { type: :object, required: %w[completion_id slot_year], properties: {
            completion_id: { type: :integer }, slot_year: { type: :integer }, acting_user_id: { type: :string }
          } }
        }
      }

      response '200', 'the Run' do
        schema one_run
      end

      response '400', 'completion_id or slot_year missing or not a whole number' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not the Run\'s member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'slot_filled (with the filling `game_id`) or run_not_active' do
        schema type: :object, properties: {
          error: { type: :string, enum: %w[slot_filled run_not_active] }, message: { type: :string },
          game_id: { type: :integer, description: 'slot_filled only: the game filling that year.' }
        }
      end

      response '422', 'not_slots, past_play_off, not_past_completion, already_cleared (use a slot move), ' \
                      'slot_out_of_range or slot_not_fitting' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/challenge_runs/{id}/past_play' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    get 'List the past Game Completions a member can pick' do
      tags 'Challenges'
      description 'The Run\'s member only (403 otherwise). With Counts past play on, the member\'s Game ' \
                  'Completions dated before their Active Slots Run started (or undated) whose game is not Cleared ' \
                  'on the Run and fits an open year, each with those years, oldest first and undated last. ' \
                  'For the past-pick picker and autocomplete. The bot names the member with `acting_user_id`.'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: false,
        description: 'Only games whose title contains this.'
      parameter name: :acting_user_id, in: :query, schema: { type: :string }, required: false

      response '200', 'the Game Completions' do
        schema type: :object, properties: {
          data: { type: :array, items: { type: :object, properties: {
            completion_id: { type: :integer }, game_id: { type: :integer }, title: { type: :string },
            cover_url: { type: :string, nullable: true, description: 'The game\'s cover; null without one.' },
            completed_at: { type: :string, format: :date, nullable: true },
            open_years: { type: :array, items: { type: :integer }, description: 'Open years of the Run it fits.' }
          } } }
        }
      end

      response '403', 'not the Run\'s member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'run_not_active' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'not_slots or past_play_off' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
