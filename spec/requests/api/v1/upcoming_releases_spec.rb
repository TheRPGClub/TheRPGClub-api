# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/upcoming_releases', type: :request do
  path '/api/v1/upcoming_releases' do
    get 'List the Release Calendar' do
      tags 'Release Calendar'
      description 'The Release Calendar (spec #389): GameDB\'s Upcoming Releases in calendar order. An ' \
                  'Upcoming Release is one game\'s Releases that share a date and Date Precision, across ' \
                  'platforms and regions (Japan included). Placement: a `month` entry before day 1 of its ' \
                  'month, a `day` entry on its date, a `quarter` entry after its last month, a `year` entry ' \
                  'after December and that year\'s Q4, `tba` last; ties break on game title, then game id. ' \
                  'Without `month` the window runs from today (UTC calendar day) forward: a `day` entry counts ' \
                  'on and after its date, `month`/`quarter`/`year` until their whole period has ended, `tba` ' \
                  'always. Any signed-in member; belongs to the Release Calendar Feature, so a member who ' \
                  'cannot use it gets 404 `not_found`; the service token is not gated.'
      produces 'application/json'
      parameter name: :month, in: :query, required: false, schema: { type: :string, pattern: '^\d{4}-\d{2}$', example: '2027-07' },
        description: 'A calendar month, past or future: the entries placed in it (its days, the month itself, a ' \
                     'quarter ending in it and, for December, the year). Never TBA. A malformed month is a 422 ' \
                     '`invalid_month`.'
      parameter name: :platform_id, in: :query, required: false, style: :form, explode: true,
        schema: { type: :array, items: { type: :integer } },
        description: 'Keeps an entry when any of its Releases is on one of these platforms; the entry still ' \
                     'lists all its Releases. Repeat it (`platform_id=1&platform_id=2`, or `platform_id[]=1&platform_id[]=2`) ' \
                     'or comma-separate the ids. A non-id is a 422 `invalid_platform_id`.'
      parameter name: :game_id, in: :query, required: false, style: :form, explode: true,
        schema: { type: :array, items: { type: :integer } },
        description: 'Limits the entries to these games. Repeat it (`game_id=1&game_id=2`, or `game_id[]=1&game_id[]=2`) or ' \
                     'comma-separate the ids. A non-id is a 422 `invalid_game_id`.'
      parameter name: :per_game, in: :query, required: false, schema: { type: :string, enum: %w[next] },
        description: '`next` keeps only each game\'s earliest entry (after the other filters). Any other value ' \
                     'is a 422 `invalid_per_game`.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 100 }, required: false

      response '200', 'the Upcoming Releases, in calendar order' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/UpcomingRelease' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }, required: %w[data meta]
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the viewer cannot use the Release Calendar Feature' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'a malformed month, id or per_game' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
