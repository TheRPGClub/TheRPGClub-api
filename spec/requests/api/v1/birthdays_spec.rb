# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/birthdays', type: :request do
  path '/api/v1/birthdays/upcoming' do
    get 'List Upcoming Birthdays' do
      tags 'Users'
      description 'Upcoming Birthdays (spec #396): the shared Birthdays falling from today through today + 29 ' \
                  'days, counted in club days (America/New_York), across the year end. Only members who share ' \
                  'their Birthday and are still in the server are listed. A 29 February Birthday falls on 28 ' \
                  'February in years that aren\'t leap years. Ordered by `on`, then by `display_name`. Never ' \
                  'the year or the age. `next` is the first shared Birthday after those 30 days, without ' \
                  'the member (null when nobody shares one). Any signed-in member or the service token; ' \
                  'Birthdays aren\'t a Feature, so nothing gates it.'
      produces 'application/json'

      response '200', 'the Upcoming Birthdays, soonest first' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/UpcomingBirthday' } },
          next: { allOf: [ { '$ref' => '#/components/schemas/NextBirthday' } ], nullable: true }
        }, required: %w[data next]
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
