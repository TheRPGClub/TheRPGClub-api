# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/goty_votes', type: :request do
  path '/api/v1/goty_votes' do
    get 'List GOTY Votes' do
      tags 'GOTY Vote'
      description 'Every year\'s GOTY Vote, newest first, with its derived `phase`, dates and, once it is ' \
                  'decided, each Award\'s `winners` (game and how it was decided). Behind the ' \
                  '`goty_vote` Feature. The lifecycle creates each year\'s GOTY Vote with the default schedule: ' \
                  'nominations open January 1 of the next year at 00:00, voting opens at noon on the first Friday ' \
                  'on or after January 15 and closes at the end of that Sunday (US Eastern).'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'GOTY Votes' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/GotyVoteSummary' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/goty_votes/{year}' do
    parameter name: :year, in: :path, type: :integer, description: 'The year the GOTY Vote decides, e.g. 2026'

    get 'Show a GOTY Vote' do
      tags 'GOTY Vote'
      description 'The year\'s GOTY Vote: its `phase` (derived at read time), dates and the three Awards. Each ' \
                  'Award lists its ballot (the candidates frozen when voting opens; before then the live ' \
                  'ballot: GOTM and NR-GOTM of the Year list every winner of the rounds whose `month_year` falls ' \
                  'in the year, each game once, and Game of the Year every nominated game once, in the order ' \
                  'first nominated), the viewer\'s own votes and cap, any runoff or pending tie, and the ' \
                  'winner with how it was decided. As for GOTM votes, the tally\'s counts are hidden from ' \
                  'members while that ballot is open (Admins and the service see them), and once the GOTY Vote ' \
                  'is decided the `result` names every voter. Behind the `goty_vote` Feature. 404 for a year ' \
                  'with no GOTY Vote.'
      produces 'application/json'
      parameter name: :user_id, in: :query, schema: { type: :string }, required: false,
                description: 'Admins and the service: show this member\'s own votes (the bot\'s vote panels). ' \
                             'Members always see their own.'

      response '200', 'GOTY Vote' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GotyVote' } }, required: %w[data]
      end

      response '404', 'no GOTY Vote for the year' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Move a GOTY Vote\'s dates' do
      tags 'GOTY Vote'
      description 'Admin: moves the nominations open, voting open and voting close. Dates must run nominations ' \
                  'open < voting opens < voting closes. Moving `voting_opens_at` alone keeps the default weekend ' \
                  'window; "close voting now" is `voting_closes_at` set to now. Once voting has opened only ' \
                  '`voting_closes_at` moves. Behind the `goty_vote` Feature.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              nominations_open_at: { type: :string, format: 'date-time' },
              voting_opens_at: { type: :string, format: 'date-time' },
              voting_closes_at: { type: :string, format: 'date-time' }
            }
          }
        },
        required: %w[data]
      }

      response '200', 'GOTY Vote' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GotyVote' } }, required: %w[data]
      end

      response '422', 'dates out of order, `voting_opened` (only the close moves once voting has opened) or ' \
                      '`goty_vote_decided`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not an Admin' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no GOTY Vote for the year' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/goty_votes/{year}/nominations' do
    parameter name: :year, in: :path, type: :integer, description: 'The year the GOTY Vote decides, e.g. 2026'

    get 'List Game of the Year nominations' do
      tags 'GOTY Vote'
      description 'Every Game of the Year nomination for the year, oldest first, each with its nominator and game ' \
                  '(nominations carry no reason). `user_id` narrows it to one member\'s (at most three). Behind the `goty_vote` ' \
                  'Feature. 404 for a year with no GOTY Vote.'
      produces 'application/json'
      parameter name: :user_id, in: :query, schema: { type: :string }, required: false,
                description: 'Only this member\'s nominations'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'nominations' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/GotyNomination' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '404', 'no GOTY Vote for the year' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Nominate a game for Game of the Year' do
      tags 'GOTY Vote'
      description 'Nominates a game for the year\'s Game of the Year while the GOTY Vote is `nominating` (from ' \
                  '`nominations_open_at` until `voting_opens_at`). A member nominates for themselves; the ' \
                  'service names the member in `user_id`. Each member nominates up to three games a year, each ' \
                  'once: posting a game the member already nominated changes nothing (200). The game ' \
                  'must be eligible (see `GET /games/{id}/goty_eligibility`); playing it is not required. ' \
                  'Behind the `goty_vote` Feature.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              gamedb_game_id: { type: :integer },
              user_id: { type: :string, description: 'The member, from the service only. A member may send ' \
                                                       'their own id or leave it out.' }
            },
            required: %w[gamedb_game_id]
          }
        },
        required: %w[data]
      }

      response '201', 'nomination created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GotyNomination' } }
      end

      response '200', 'the member had already nominated the game; nothing changed' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GotyNomination' } }
      end

      response '422', '`nominations_closed` outside the nomination window, `nomination_cap_reached` at three, ' \
                      '`not_released_in_year` or `release_unknown` (ask staff to record its release) for an ' \
                      'ineligible game, or `user_id_required` from the service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'a member nominating for someone else' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no GOTY Vote for the year, no such game, or (service) no such member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing `data` or `gamedb_game_id`' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/goty_votes/{year}/nominations/{id}' do
    parameter name: :year, in: :path, type: :integer, description: 'The year the GOTY Vote decides, e.g. 2026'
    parameter name: :id, in: :path, type: :integer, description: 'The nomination id'

    delete 'Withdraw or remove a Game of the Year nomination' do
      tags 'GOTY Vote'
      description 'The owner withdraws their nomination while the GOTY Vote is `nominating`; an Admin (or the ' \
                  'service) removes any nomination at any time before voting opens. An Admin removing someone ' \
                  'else\'s nomination must give a `reason` (1 to 250 characters), and a ' \
                  '`goty_nomination_deleted` bot job announces the removal (payload: year, user_id, game_title, ' \
                  'deleted_by_user_id, reason). Owners and the service delete plainly, with no job. Behind the ' \
                  '`goty_vote` Feature.'
      produces 'application/json'
      parameter name: :reason, in: :query, schema: { type: :string, maxLength: 250 }, required: false,
                description: 'Why staff removed it. Required when an Admin removes someone else\'s nomination.'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/NominationDeletedResponse'
      end

      response '403', 'not the owner, and not an Admin' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', '`nominations_closed`: voting has opened, or (for the owner) nominations are not open; ' \
                      '`reason_required` or `reason_too_long` from an Admin removing someone else\'s nomination' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no such nomination for the year' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/games/{id}/goty_eligibility' do
    parameter name: :id, in: :path, type: :integer, description: 'GameDB game id'
    parameter name: :year, in: :query, required: true, schema: { type: :integer }, description: 'The GOTY Vote year'

    get 'Check Game of the Year eligibility' do
      tags 'GOTY Vote'
      description 'Whether the game may be nominated for the year\'s Game of the Year, so the bot and the ' \
                  'website can grey out ineligible games in search. Eligible when the game\'s earliest dated ' \
                  'Release (IGDB or Manual, any region or platform; a year-only date counts) falls in the year; ' \
                  'with no dated Release, its initial release date is judged instead, and with neither the ' \
                  'reason is `release_unknown`. Each GameDB game stands alone: a remake is judged by its own ' \
                  'Releases. Behind the `goty_vote` Feature. 400 without a valid `year`.'
      produces 'application/json'

      response '200', 'eligibility' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GotyEligibility' } },
               required: %w[data]
      end

      response '400', 'missing or invalid year' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no such game' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/goty_votes/{year}/votes' do
    parameter name: :year, in: :path, type: :integer, description: 'The year the GOTY Vote decides, e.g. 2026'

    post 'Vote in a GOTY Vote Award' do
      tags 'GOTY Vote'
      description 'Casts or toggles a vote in one Award, by the GOTM round rules. While voting is open a member ' \
                  'holds up to half the Award\'s candidates in votes (at least 1, computed at cast time); voting ' \
                  'for a game already voted for takes the vote back (200), and voting at the cap removes the ' \
                  'oldest vote, which `removed_votes` and `warning` report. During the runoff only a tied Award ' \
                  'takes votes, one each, for one of its tied games. An Award with a single candidate wins ' \
                  'without a vote. A member votes for themselves; the service names the member in `user_id`. ' \
                  'Behind the `goty_vote` Feature.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              award: { type: :string, enum: Goty::AWARDS.keys },
              gamedb_game_id: { type: :integer },
              user_id: { type: :string, description: 'The member, from the service only. A member may send ' \
                                                       'their own id or leave it out.' }
            },
            required: %w[award gamedb_game_id]
          }
        },
        required: %w[data]
      }

      response '201', 'vote placed' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GotyVoteCastResult' } }
      end

      response '200', 'the vote was taken back' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GotyVoteCastResult' } }
      end

      response '422', '`voting_closed` (no ballot open for the Award), `not_a_candidate`, `uncontested` (a single ' \
                      'candidate), `not_in_runoff`, `unknown_award`, or `user_id_required` from the service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'a member voting for someone else' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no GOTY Vote for the year, or (service) no such member' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/goty_votes/{year}/awards/{award}/resolve_tie' do
    parameter name: :year, in: :path, type: :integer, description: 'The year the GOTY Vote decides, e.g. 2026'
    parameter name: :award, in: :path, schema: { type: :string, enum: Goty::AWARDS.keys }

    post 'Settle a GOTY Vote Award tie' do
      tags 'GOTY Vote'
      description 'Admin: picks the Award\'s winner from its tied games, decided by `admin`. The last resort once ' \
                  'a runoff tied again; also allowed while the runoff is open. Once no Award is pending the ' \
                  'GOTY Vote is decided. Behind the `goty_vote` Feature.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: { gamedb_game_id: { type: :integer } },
                              required: %w[gamedb_game_id] } },
        required: %w[data]
      }

      response '200', 'GOTY Vote' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GotyVote' } }, required: %w[data]
      end

      response '422', '`no_tie` (the Award is not tied) or `invalid_pick` (not one of its tied games)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not an Admin' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no GOTY Vote for the year' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
