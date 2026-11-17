# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/challenges', type: :request do
  acting_user_id = {
    type: :string,
    description: 'Service only, required on every write: the Discord user id of the member the bot acts for. ' \
                 'Their stored roles decide what they may do, and the Feature Flag applies to them.'
  }
  pool = {
    type: :object,
    description: 'The Pool (challenge_format pool). On edit, only the keys given change.',
    properties: {
      franchise_ids: { type: :array, items: { type: :integer }, description: 'GameDB franchises whose games are in the Pool.' },
      collection_ids: { type: :array, items: { type: :integer }, description: 'GameDB collections whose games are in the Pool.' },
      included_game_ids: { type: :array, items: { type: :integer }, description: 'Games in the Pool whatever their franchise.' },
      excluded_game_ids: { type: :array, items: { type: :integer }, description: 'Games left out of the chosen franchises and collections.' },
      target: { oneOf: [ { type: :integer, minimum: 1 }, { type: :string, enum: %w[all] } ],
                description: 'Cleared games needed to Finish, or "all" for every game in the Pool. Required on create.' }
    }
  }
  slots = {
    type: :object,
    description: 'The slot range (challenge_format slots): one slot per release year. On edit, only the keys ' \
                 'given change; first_year and last_year are required on create.',
    properties: {
      first_year: { oneOf: [ { type: :integer, minimum: 1900, maximum: 2100 }, { type: :string, enum: %w[birth_year] } ],
                    description: 'A fixed year, or "birth_year" for each member\'s birth year (a Run then needs ' \
                                 'their Birth Date, and shows the year).' },
      last_year: { oneOf: [ { type: :integer, minimum: 1900, maximum: 2100 }, { type: :string, enum: %w[current_year] } ],
                   description: 'A fixed year, or "current_year" for a range that gains a slot every 1 January. ' \
                                'Not before a fixed first year.' },
      counts_past_play: { type: :boolean, description: 'Counts past play: members may pick Game Completions dated ' \
                                                       'before their Run started for open slots. Always Open ' \
                                                       'Challenges only (422 on Seasonal); false when left out on ' \
                                                       'create.' }
    }
  }
  assignment = {
    type: :object,
    description: 'The Edition calendar (challenge_format assignment, Secret Santa) as MM-DD, coming in this order ' \
                 'through the year; 29 February is refused. Any day left out is the Secret Santa default ' \
                 '(12-01, 12-15, 12-25). An Assignment Challenge is Always Open with no end date. Saving it opens ' \
                 'the Edition whose sign-up is due today; a change moves an Edition still in sign-up that nobody ' \
                 'has joined to the new dates, and otherwise applies from the next Edition.',
    properties: {
      signup_cutoff: { type: :string, example: '12-01', description: 'Sign-up closes at the start of this day.' },
      pick_deadline: { type: :string, example: '12-15' },
      reveal: { type: :string, example: '12-25', description: 'The Edition is named by its reveal\'s year.' }
    }
  }
  tint = {
    oneOf: [ { type: :string, enum: Challenges::Tint::CURATED.keys },
             { type: :object, required: %w[fill hi],
               properties: { fill: { type: :string, example: '#5a2d82' }, hi: { type: :string, example: '#d9b8ff' } } } ],
    nullable: true,
    description: 'The Challenge tint: a curated tint by name, any `{ fill, hi }` as #rrggbb, or null for the ' \
                 'Challenge\'s curated tint. A pair must keep type readable (4.5:1): paper #f4f4f0 on the fill, ' \
                 'and the hi on ink #0b0b0d and #141417; otherwise 422 `invalid_challenge`. Left out on create, ' \
                 'the Challenge gets its curated tint. Not a rule: editable after Runs exist.'
  }
  writable = {
    acting_user_id: acting_user_id,
    name: { type: :string, maxLength: Challenge::NAME_MAX },
    description: { type: :string },
    challenge_format: { type: :string, enum: Challenge::FORMATS,
                        description: 'pool, slots or assignment (Secret Santa). ' \
                                     'Locked once the Challenge has a Run.' },
    schedule: { type: :string, enum: Challenge::SCHEDULES, description: 'Locked once the Challenge has a Run.' },
    ends_on: { type: :string, format: :date, nullable: true,
               description: 'Always Open only: the last Open day (club time zone). Stays editable after Runs exist, ' \
                            'until the day after it, when the Challenge Closes for good.' },
    season: { type: :object, nullable: true,
              description: 'Seasonal only: start and end as MM-DD, repeating every year; the end may come before ' \
                           'the start to cross the new year. Locked once the Challenge has a Run.',
              properties: { start: { type: :string, example: '12-01' }, end: { type: :string, example: '02-28' } } },
    pool: pool,
    slots: slots,
    assignment: assignment,
    tint: tint
  }
  refusal = 'Refusals carry `{ error, message }`; `message` is written for members (403 `forbidden`, 422 ' \
            '`invalid_challenge`).'

  path '/api/v1/challenges' do
    get 'List Challenges' do
      tags 'Challenges'
      description 'Members (the `challenges` Feature). Newest first. Hidden Challenges are listed only for ' \
                  'Moderators and above and for their Host. The bot may name the member it reads for with ' \
                  '`acting_user_id`, without which it sees what any member sees.'
      produces 'application/json'
      parameter name: :open, in: :query, required: false, schema: { type: :string, enum: %w[true false] },
        description: 'Only the Challenges Open (true) or Closed (false) today, in the club\'s time zone.'
      parameter name: :challenge_format, in: :query, required: false, schema: { type: :string, enum: Challenge::FORMATS }
      parameter name: :q, in: :query, required: false, schema: { type: :string },
        description: 'Only the Challenges whose name contains `q`, ignoring case (surrounding spaces are ' \
                     'dropped; empty means no filter). For the bot\'s Challenge autocomplete.'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'Challenges' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Challenge' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '400', 'an unknown `open` or `challenge_format`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the Feature is Off, or Preview and the caller is not an Admin or Superadmin' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a Challenge' do
      tags 'Challenges'
      description 'Regulars, Moderators, Admins and Superadmins (a member without the Regulars role gets 403 ' \
                  '"You need the Regulars role to create a Challenge."). The acting member becomes the Host, or ' \
                  'the club with `hosted_by_club` (Moderator and above). A name another Challenge already has ' \
                  'is allowed and adds a `duplicate_name` warning to `meta.warnings`. Queues a ' \
                  '`challenge_announce` bot job (payload ChallengeAnnounceJobPayload, event `challenge_created`). ' +
                  refusal
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: writable.merge(hosted_by_club: { type: :boolean, description: 'Moderator and above.' }),
            required: %w[name challenge_format schedule],
            description: 'Send the settings of the chosen Format: `pool`, `slots` or `assignment` (optional).'
          }
        },
        required: %w[data]
      }

      response '201', 'created' do
        schema type: :object, properties: {
          data: { '$ref' => '#/components/schemas/Challenge' },
          meta: { type: :object, properties: {
            warnings: { type: :array, items: { '$ref' => '#/components/schemas/ChallengeWarning' } }
          } }
        }
      end

      response '400', 'missing `data`, or the bot named no `acting_user_id`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not a Regular or staff, club-hosted without Moderator, or (bot) `feature_unavailable`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'invalid_challenge: a missing or invalid field, an empty or unknown Pool, a slot range that ' \
                      'ends before it starts, an Edition calendar out of order, a Seasonal or ending Assignment ' \
                      'Challenge' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/challenges/pool_preview' do
    post 'Preview the games a draft Pool resolves to' do
      tags 'Challenges'
      description 'Members. The games a Pool definition resolves to against the GameDB now, oldest release ' \
                  'first, paginated, so the bot and the website can show them before saving. 422 ' \
                  '`invalid_challenge` for an empty definition, unknown ids, or a game both included and excluded.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: pool.merge(properties: pool[:properties].except(:target)) },
        required: %w[data]
      }

      response '200', 'the Pool\'s games' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/GameSummary' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '422', 'not a Pool the GameDB can resolve' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/challenges/pool_sources' do
    get 'Find franchises and collections to build a Pool from' do
      tags 'Challenges'
      description 'Members. GameDB franchises, then collections, whose name contains `q` (ignoring case), at ' \
                  'most 25 of each, with how many games each has.'
      produces 'application/json'
      parameter name: :q, in: :query, required: true, schema: { type: :string }

      response '200', 'matching franchises and collections' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/ChallengePoolSource' } }
        }
      end

      response '400', 'no `q`' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/challenges/{id}' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    get 'Show a Challenge' do
      tags 'Challenges'
      description 'Members. A hidden Challenge is 404 except for Moderators and above and its Host. Adds the ' \
                  'Pool\'s `game_count` and `run_count`.'
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }

      response '200', 'the Challenge' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Challenge' } }
      end

      response '404', 'not found, or hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Edit a Challenge' do
      tags 'Challenges'
      description 'The Host, for their own; any Moderator or above, for a club-hosted one. Only the keys given ' \
                  'change. Once the Challenge has any Run its rules are locked: a change to the Format, ' \
                  'schedule, Season, Pool or slot range is 409 `rules_locked` with the `fields` it would change ' \
                  '(sending them unchanged is fine). Name, description and end date stay editable, except that an ' \
                  'Always Open Challenge that reached its end date is Closed for good (`ended_at`): a change to its ' \
                  'schedule or end date is 422 `invalid_challenge`. ' + refusal
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object, properties: { data: { type: :object, properties: writable } }, required: %w[data]
      }

      response '200', 'edited' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Challenge' } }
      end

      response '403', 'not the Host (or, club-hosted, not a Moderator)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'rules_locked' do
        schema type: :object, properties: {
          error: { type: :string, enum: %w[rules_locked] }, message: { type: :string },
          fields: { type: :array, items: { type: :string, enum: %w[challenge_format schedule season pool slots] } }
        }
      end

      response '422', 'invalid_challenge, including a new schedule or end date for a Challenge Closed for good' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a Challenge' do
      tags 'Challenges'
      description 'The Host, while it has no Runs (409 `has_runs` after); a Moderator or above removes any ' \
                  'Challenge, its Runs included. Write: the bot sends `acting_user_id` as a query parameter.'
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }

      response '200', 'deleted' do
        schema type: :object, properties: {
          data: { type: :object, properties: { id: { type: :integer }, deleted: { type: :boolean } } }
        }
      end

      response '403', 'neither the Host nor a Moderator' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'has_runs: the Host cannot delete a Challenge with Runs' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  %w[hide unhide].each do |action|
    path "/api/v1/challenges/{id}/#{action}" do
      parameter name: :id, in: :path, schema: { type: :integer }, required: true

      post "#{action.capitalize} a Challenge" do
        tags 'Challenges'
        description "Moderator and above. #{action == 'hide' ? 'Hides it from members (not its Host).' : 'Shows it again.'} " \
                    'The bot sends `{ "data": { "acting_user_id": "..." } }`.'
        produces 'application/json'

        response '200', 'the Challenge' do
          schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Challenge' } }
        end

        response '403', 'not a Moderator or above' do
          schema '$ref' => '#/components/schemas/Error'
        end
      end
    end
  end

  path '/api/v1/challenges/{id}/tint' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    put 'Change a Challenge\'s tint' do
      tags 'Challenges'
      description 'The Host, for their own (PATCH takes `tint` too), and a Moderator or above for any Challenge, ' \
                  'which PATCH does not let them edit. 403 "Only the Host or a Moderator can change this ' \
                  'Challenge\'s tint."; 422 `invalid_challenge` without `tint`, or for a tint PATCH would refuse.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: { acting_user_id: acting_user_id, tint: tint },
                              required: %w[tint] } },
        required: %w[data]
      }

      response '200', 'the Challenge with its new tint' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Challenge' } }
      end

      response '403', 'neither the Host nor a Moderator' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'invalid_challenge' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/challenges/{id}/host' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    put 'Hand a Challenge to another Host' do
      tags 'Challenges'
      description 'Moderator and above. Hands it to another member (who needs no role) or, with ' \
                  '`hosted_by_club`, to the club. 422 `invalid_challenge` for neither, or an unknown member.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: {
          acting_user_id: acting_user_id, host_user_id: { type: :string }, hosted_by_club: { type: :boolean }
        } } },
        required: %w[data]
      }

      response '200', 'the Challenge with its new Host' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Challenge' } }
      end

      response '403', 'not a Moderator or above' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'invalid_challenge' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
