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
    description: 'The Pool (challenge_format pool): a Run Finishes by Clearing every Core Game plus ' \
                 '`optional_target` Optional Games. Sources (a linked Game List, Franchises and Series) only add ' \
                 'Optional Games, ' \
                 'leaving out Add-ons (games with a parent game); a game is Core only when listed in ' \
                 '`core_game_ids` (docs/adr/0014). Needs at least one Core Game or a target of at least 1, and ' \
                 'the target can\'t exceed the Optional Games when saved. A game may be in only one of the ' \
                 'three game lists. On edit, only the keys given change; none of it is locked once Runs exist.',
    properties: {
      franchise_ids: { type: :array, items: { type: :integer }, description: 'Franchises whose games (not Add-ons) are Optional Games.' },
      collection_ids: { type: :array, items: { type: :integer }, description: 'Series (IGDB collections) whose games (not Add-ons) are Optional Games.' },
      core_game_ids: { type: :array, items: { type: :integer }, description: 'Core Games: every Run must Clear them.' },
      optional_game_ids: { type: :array, items: { type: :integer }, description: 'Optional Games picked by hand, whatever their sources; Add-ons allowed.' },
      excluded_game_ids: { type: :array, items: { type: :integer }, description: 'Games kept out though a source has them.' },
      optional_target: { type: :integer, minimum: 0, default: 0,
                         description: 'Optional Games a Run must Clear besides every Core Game. 0 when left out on create.' },
      game_list_id: { type: :integer,
                      description: 'Create only (422 on edit): start the Pool from this Game List. Its games come in ' \
                                   'as Core Games, except those this request makes Optional or excludes, and the ' \
                                   'list stays linked: games later added to it arrive as Optional Games. A member\'s ' \
                                   'own list, for a Challenge they host; a club list, for a club-hosted one (403 ' \
                                   '"Only a Game List\'s owner can start a Challenge from it, hosted by them; a ' \
                                   'club list, a Moderator or above, for a club-hosted Challenge."). 422 for a ' \
                                   'list the member can\'t see.' }
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
      description 'Any member, for a Slots or Pool Challenge; an Assignment Challenge needs a Moderator or above ' \
                  '(403 "Only Moderators and above can create an Assignment Challenge."). The acting member becomes the Host, or ' \
                  'the club with `hosted_by_club` (Moderator and above). A name another Challenge already has ' \
                  'is allowed and adds a `duplicate_name` warning to `meta.warnings`. Queues a ' \
                  '`challenge_announce` bot job (payload ChallengeAnnounceJobPayload, event `challenge_created`). ' \
                  '`pool.game_list_id` starts a Pool from a Game List (ticket api#448). ' +
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

      response '403', 'Assignment or club-hosted without Moderator, a Game List that isn\'t theirs to link, or ' \
                      '(bot) `feature_unavailable`' do
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
      description 'Members. The games a Pool definition resolves to against the GameDB now, Core and Optional ' \
                  'together, oldest release first, paginated, so the bot and the website can show them before ' \
                  'saving (an empty definition has none). 422 `invalid_challenge` for unknown ids, or a game in ' \
                  'more than one of the core, optional and excluded lists.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: pool.merge(properties: pool[:properties].except(:optional_target)) },
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
                  'Pool\'s Optional Games and counts, and `run_count`.'
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
      description "The Host, for their own; any Moderator or above, for any Challenge (403 \"Only the Host or a Moderator can edit this Challenge.\"). " \
                  'Only the keys given ' \
                  'change. Once the Challenge has any Run its rules are locked: a change to the Format, ' \
                  'schedule, Season or slot range is 409 `rules_locked` with the `fields` it would change ' \
                  '(sending them unchanged is fine). Name, description and end date stay editable, except that an ' \
                  'Always Open Challenge that reached its end date is Closed for good (`ended_at`): a change to its ' \
                  'schedule or end date is 422 `invalid_challenge`. A Pool\'s games, sources and Optional ' \
                  'target stay editable with Runs: the Runs are then brought up to date (one that now meets the ' \
                  'goal Finishes), and a save that adds Core Games or raises the target queues one ' \
                  '`challenge_dm` `pool_goal_changed` per member with an Active Run who keeps Challenge DMs on. ' \
                  'With `add_to_list`, the games the edit newly makes Core or Optional by hand also go into the ' \
                  'linked Game List (403 "Only the Game List\'s owner can add games to it from this ' \
                  'Challenge." unless the viewer is ' \
                  'the list\'s owner, or staff for a club list on a club-hosted Challenge: see ' \
                  '`pool.game_list.can_add`; 422 without a linked list; 422 `list_full` past 500 games, saving ' \
                  'nothing). Editing a removed Core Game out of the Pool clears its list notice. Switching the ' \
                  'Format to Assignment needs a Moderator or above (403 "Only Moderators and above can create ' \
                  'an Assignment Challenge."). A Pool that leaves Pool ends its Game List link (clearing its list ' \
                  'notices) and declines its pending Pool Proposals. A Pool already short of its Optional target ' \
                  '(a source shrank) still saves an edit that leaves it no shorter: the target not raised and no ' \
                  'Optional Game fewer. ' + refusal
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object, properties: { data: { type: :object, properties: writable.merge(
          add_to_list: { type: :boolean, description: 'Also add the games put in the Pool by hand to the linked Game List.' }
        ) } }, required: %w[data]
      }

      response '200', 'edited' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Challenge' } }
      end

      response '403', 'neither the Host nor a Moderator, a switch to Assignment below Moderator, or `add_to_list` ' \
                      'from someone who may not touch the list' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'rules_locked' do
        schema type: :object, properties: {
          error: { type: :string, enum: %w[rules_locked] }, message: { type: :string },
          fields: { type: :array, items: { type: :string, enum: %w[challenge_format schedule season slots assignment] } }
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

  path '/api/v1/challenges/{id}/pool_progress' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    get "Read a Pool Challenge's progress by game" do
      tags 'Challenges'
      description 'Members. The Pool\'s games, oldest release first, paginated, each with the members who Cleared ' \
                  'it (on a Run of any status, each member once at their earliest Clear) and who have it In ' \
                  'Progress (on an Active Run, or a Finished one whose window is open). The Runs read are those ' \
                  'of the Season running now, or of the last Season while the Challenge is Closed, and every Run ' \
                  'of an Always Open Challenge. 404 for a Challenge hidden from the caller; 422 `not_pool` for ' \
                  'Slots and Assignment.'
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'the Pool\'s games with their progress' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/ChallengePoolGameProgress' } },
          meta: { allOf: [ { '$ref' => '#/components/schemas/PaginationMeta' }, { type: :object, properties: {
            window: { '$ref' => '#/components/schemas/ChallengeSeasonDates', nullable: true,
                      description: 'The Season read; null for an Always Open Challenge.' }
          } } ] }
        }
      end

      response '404', 'not found, or hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'not a Pool Challenge' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/challenges/{id}/tint' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    put 'Change a Challenge\'s tint' do
      tags 'Challenges'
      description 'The Host, for their own, and a Moderator or above for any Challenge (PATCH takes `tint` ' \
                  'too). 403 "Only the Host or a Moderator can change this ' \
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
                  '`hosted_by_club`, to the club. A new Host ends the link to a Game List: its Optional Games ' \
                  'from the list stay, as picked by hand, and its list notices go. 422 `invalid_challenge` for ' \
                  'neither, or an unknown member.'
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

  { 'remove' => 'Remove a list notice\'s game', 'keep' => 'Keep a list notice\'s game' }.each do |resolution, summary|
    path "/api/v1/challenges/{id}/list_notices/{notice_id}/#{resolution}" do
      parameter name: :id, in: :path, schema: { type: :integer }, required: true
      parameter name: :notice_id, in: :path, schema: { type: :integer }, required: true

      post summary do
        tags 'Challenges'
        description 'Whoever may edit the Challenge (the Host or a Moderator). A list notice says a Core Game\'s ' \
                    'entry left the linked Game List (Challenge `list_notices`). ' +
                    (if resolution == 'remove'
                       'Takes the game out of the Pool as a Pool edit would (Runs are brought up to date), ' \
                         'excluding it when another source still holds it, '
                     else
                       'Leaves the game a Core Game, '
                     end) +
                    'and clears the notice. The bot sends `{ "data": { "acting_user_id": "..." } }`.'
        produces 'application/json'

        response '200', 'the Challenge' do
          schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Challenge' } }
        end

        response '403', 'neither the Host nor a Moderator' do
          schema '$ref' => '#/components/schemas/Error'
        end

        response '404', 'no such notice on this Challenge, or a Challenge hidden from the caller' do
          schema '$ref' => '#/components/schemas/Error'
        end

        next unless resolution == 'remove'

        response '422', 'invalid_challenge: the Pool would be left without a goal, or the target above its ' \
                        'Optional Games' do
          schema '$ref' => '#/components/schemas/Error'
        end
      end
    end
  end
end
