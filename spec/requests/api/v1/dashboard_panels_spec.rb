# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/dashboard_panels', type: :request do
  path '/api/v1/users/{user_id}/dashboard_panels' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord user id of the member. Must be the signed-in member.'

    get 'Show a member\'s Dashboard Panels' do
      tags 'Dashboard Panels'
      description 'The panels the member shows below the current issue on their own dashboard, in their ' \
                  'order: only the panels they can see right now (a Feature they are shown; `birthdays` needs ' \
                  'none). A member who never saved a list gets the club default (news, now_playing_club, ' \
                  'releases, achievements_club, challenges_club). Panels they can\'t see right now are left out ' \
                  'but kept. `catalogue` lists every panel they can see, shown or not, with its scope and ' \
                  'whether it is new to them. `customised` says whether the member saved their own list. Only ' \
                  'the member themself may read it; another member, staff and the bot\'s service token get 403.'
      produces 'application/json'

      response '200', 'dashboard panels' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/DashboardPanels' } },
          required: %w[data]
      end

      response '403', 'forbidden: caller is not the member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    put 'Replace a member\'s Dashboard Panels' do
      tags 'Dashboard Panels'
      description 'Replaces the list the member sees with `panels`, in order: show, hide and reorder all send ' \
                  'the whole list. There is no limit. Panels the member can\'t see right now are kept, after ' \
                  'the sent ones and in their existing order. An unknown key or a key sent twice returns 422 ' \
                  'and changes nothing; its `error` says why. A key the member can\'t see right now is ' \
                  'accepted and kept. Saved keys the API no longer knows are dropped. The first save makes ' \
                  'the list the member\'s own, so later changes to the club default no longer reach them, and ' \
                  'an empty list stays empty. Returns the whole document, as GET does.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              panels: {
                type: :array, items: { type: :string },
                description: 'Dashboard Panel keys, in order. May be empty.',
                example: %w[news reviews birthdays]
              }
            },
            required: %w[panels]
          }
        },
        required: %w[data]
      }

      response '200', 'saved dashboard panels' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/DashboardPanels' } },
          required: %w[data]
      end

      response '422', 'not a list, unknown panel, or panel sent twice' do
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

    delete 'Reset a member\'s Dashboard Panels to the club default' do
      tags 'Dashboard Panels'
      description 'Drops the member\'s saved list, hidden panels included, so they follow the club default ' \
                  'again, and later changes to it reach them. `customised` is false afterwards and true again ' \
                  'after their next save. Resetting a member who already follows the default changes nothing. ' \
                  'Returns the whole document, as GET does.'
      produces 'application/json'

      response '200', 'dashboard panels, back to the club default' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/DashboardPanels' } },
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

  path '/api/v1/users/{user_id}/dashboard_panels/seen' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord user id of the member. Must be the signed-in member.'

    post 'Mark the Dashboard Panel catalogue as seen' do
      tags 'Dashboard Panels'
      description 'Called when the member opens dashboard edit mode. Records the moment, so no panel in the ' \
                  '`catalogue` is `new` to them until another panel is added to the site. A member who has ' \
                  'never called it sees nothing as new. Returns the whole document, as GET does.'
      produces 'application/json'

      response '200', 'dashboard panels, nothing new' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/DashboardPanels' } },
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
