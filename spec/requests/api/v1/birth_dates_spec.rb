# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/birth_dates', type: :request do
  path '/api/v1/users/{user_id}/birth_date' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord user id of the member.'

    get 'Show a member\'s Birth Date' do
      tags 'Users'
      description 'The member\'s Birth Date and how many times they may still set or change it this calendar ' \
                  'month. Only the member and staff (Moderators and above) may read it; another member gets ' \
                  '403. The bot\'s service token must name the member it acts for in `acting_user_id`, and ' \
                  'the API checks that member the same way.'
      produces 'application/json'

      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string },
        description: 'Service token only (required): the Discord user the bot acts for.'

      response '200', 'birth date' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/BirthDate' } },
          required: %w[data]
      end

      response '400', 'service token without acting_user_id' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is neither the member nor staff' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    put 'Set a member\'s Birth Date' do
      tags 'Users'
      description 'Sets the member\'s Birth Date, or removes it with null. The year is optional: `MM-DD` ' \
                  'sets a day and month alone, served back as `"05-04"`. A member may set or change their ' \
                  'own at most twice per calendar month (US Eastern), and entering it the first time counts; ' \
                  'a third change that month gets 422 with `next_change_on`, the first day of next month. ' \
                  'Setting the date it already has changes nothing and doesn\'t count. Staff (Moderators and ' \
                  'above) may set anyone\'s at any time, and their changes don\'t use up the member\'s. ' \
                  'Returns the whole document, as GET does.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              birth_date: { type: :string, nullable: true, pattern: '^(\\d{4}-)?\\d{1,2}-\\d{1,2}$',
                            example: '1990-05-04',
                            description: 'YYYY-MM-DD, from 1900 to today, or MM-DD without the year (any real ' \
                                         'month and day, 29 February included); null removes it.' },
              acting_user_id: { type: :string,
                                description: 'Service token only (required): the Discord user the bot acts for.' }
            },
            required: %w[birth_date]
          }
        },
        required: %w[data]
      }

      response '200', 'updated birth date' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/BirthDate' } },
          required: %w[data]
      end

      response '422', 'the member already changed it twice this month, or birth_date is missing, not a ' \
                      'date from 1900 to today, or not a real MM-DD month and day' do
        schema '$ref' => '#/components/schemas/BirthDateRefusal'
      end

      response '400', 'missing `data`, or service token without acting_user_id' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is neither the member nor staff' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'staff naming a member the API doesn\'t know' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
