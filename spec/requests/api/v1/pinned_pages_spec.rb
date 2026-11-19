# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/pinned_pages', type: :request do
  path '/api/v1/users/{user_id}/pinned_pages' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord user id of the member. Must be the signed-in member.'

    get 'Show a member\'s Pinned Pages' do
      tags 'Pinned Pages'
      description 'The pages the member pinned to the top of their own sidebar, in their order: only the ' \
                  'pages they can see right now (a Feature they are shown, or a staff page for their tier). ' \
                  'A member who never saved a list gets the club default (voting, games, members, news). ' \
                  'Pins they can\'t see right now are left out but kept. Only the member themself may read ' \
                  'it; another member, staff and the bot\'s service token get 403. `customised` says whether ' \
                  'the member saved their own list. The session carries the same list as `pinned_pages`, ' \
                  'and `customised` as `pinned_pages_customised`.'
      produces 'application/json'

      response '200', 'pinned pages' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/PinnedPages' } },
          required: %w[data]
      end

      response '403', 'forbidden: caller is not the member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    put 'Replace a member\'s Pinned Pages' do
      tags 'Pinned Pages'
      description 'Replaces the list the member sees with `pages`, in order: pin, unpin and reorder all ' \
                  'send the whole list. Pins the member can\'t see right now are kept, after the sent ones ' \
                  'and in their existing order. An unknown key, a key sent twice, or more than 6 pins ' \
                  '(counting the kept hidden ones) returns 422 and changes nothing. A key the member can\'t ' \
                  'see right now is accepted and kept. Saved keys the API no longer knows are dropped. The ' \
                  'first save makes the list the member\'s own, so later changes to the club default no ' \
                  'longer reach them. Returns the whole document, as GET does.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              pages: {
                type: :array, items: { type: :string }, maxItems: 6,
                description: 'Pinned Page keys, in order. May be empty.',
                example: %w[voting releases members]
              }
            },
            required: %w[pages]
          }
        },
        required: %w[data]
      }

      response '200', 'saved pinned pages' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/PinnedPages' } },
          required: %w[data]
      end

      response '422', 'not a list, unknown page, page sent twice, or more than 6 pins' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing `data` parameter' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not the member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Reset a member\'s Pinned Pages to the club default' do
      tags 'Pinned Pages'
      description 'Drops the member\'s saved list, hidden pins included, so they follow the club default ' \
                  '(voting, games, members, news) again, and later changes to it reach them. `customised` ' \
                  'is false afterwards and true again after their next save. Resetting a member who ' \
                  'already follows the default changes nothing. Returns the whole document, as GET does.'
      produces 'application/json'

      response '200', 'pinned pages, back to the club default' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/PinnedPages' } },
          required: %w[data]
      end

      response '403', 'forbidden: caller is not the member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
