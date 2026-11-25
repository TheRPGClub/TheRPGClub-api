# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/goty_votes', type: :request do
  path '/api/v1/goty_votes' do
    get 'List GOTY Votes' do
      tags 'GOTY Vote'
      description 'Every year\'s GOTY Vote, newest first, with its derived `phase` and dates. Behind the ' \
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
      description 'The year\'s GOTY Vote: its `phase` (derived at read time), dates and the three Awards with ' \
                  'their ballots. GOTM and NR-GOTM of the Year list every winner of the rounds whose `month_year` ' \
                  'falls in the year (a round with several winners puts them all on; a game that won twice ' \
                  'appears once). Game of the Year is empty until nominations land. Behind the `goty_vote` ' \
                  'Feature. 404 for a year with no GOTY Vote.'
      produces 'application/json'

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
end
