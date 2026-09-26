# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/voting_rounds', type: :request do
  round_response = { type: :object, properties: { data: { '$ref' => '#/components/schemas/VotingRound' } } }

  path '/api/v1/voting_rounds' do
    get 'List voting rounds' do
      tags 'Voting Rounds'
      description 'The GOTM / NR-GOTM round lifecycle, newest round first. `round_number` is the round being ' \
                  'nominated for, voted on and won. Open to any authenticated caller.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'voting rounds' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/VotingRound' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/voting_rounds/current' do
    get 'Show the current voting round' do
      tags 'Voting Rounds'
      description 'The one round the club is on: the lowest round not yet decided, whether it is collecting ' \
                  'nominations, voting, or awaiting a tie-break. 404 when none is scheduled. Clients read the ' \
                  'round number and `phase` from here instead of deriving them.'
      produces 'application/json'

      response '200', 'current voting round' do
        schema round_response
      end

      response '404', 'no round scheduled' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/voting_rounds/{id}' do
    parameter name: :id, in: :path, type: :integer, description: 'Round number'

    get 'Show a voting round' do
      tags 'Voting Rounds'
      produces 'application/json'

      response '200', 'voting round' do
        schema round_response
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Reschedule a voting round' do
      tags 'Voting Rounds'
      description 'Admin or service. Moving `voting_opens_at` without a `voting_closes_at` keeps the default ' \
                  'window (through the end of that weekend\'s Sunday, US Eastern). Setting `voting_closes_at` to ' \
                  'now closes voting early. 422 `round_decided` once the round is decided.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              voting_opens_at: { type: :string, format: 'date-time', description: 'When nominations close and voting opens.' },
              voting_closes_at: { type: :string, format: 'date-time', description: 'When voting closes.' },
              month_year: { type: :string, description: 'The month the winners are played, e.g. "November 2026".' }
            }
          }
        },
        required: %w[data]
      }

      response '200', 'voting round rescheduled' do
        schema round_response
      end

      response '422', 'round decided or invalid window' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not an admin or the service' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/voting_rounds/{id}/resolve_tie' do
    parameter name: :id, in: :path, type: :integer, description: 'Round number'

    post 'Break a tie' do
      tags 'Voting Rounds'
      description 'Admin or service. Records one or more of a category\'s tied games as its winners; once no ' \
                  'category is tied the round is decided and the next one scheduled. 422 `no_tie` when the ' \
                  'category is not tied, `invalid_pick` for a game outside the tie.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              category: { type: :string, enum: Voting::CATEGORIES.keys },
              gamedb_game_ids: { type: :array, items: { type: :integer }, minItems: 1 }
            },
            required: %w[category gamedb_game_ids]
          }
        },
        required: %w[data]
      }

      response '200', 'tie resolved' do
        schema round_response
      end

      response '422', 'no tie or invalid pick' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'not an admin or the service' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
