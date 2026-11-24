# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/franchises', type: :request do
  path '/api/v1/franchises' do
    get 'List franchises' do
      tags 'Franchises'
      description 'Returns the IGDB-curated game franchises. Supports `q` for case-insensitive name search.'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: false, description: 'Search term against `name`.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'franchises list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/Franchise' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a franchise, or upsert one by IGDB id' do
      tags 'Franchises'
      description 'Two uses. Without `igdb_franchise_id`, a Regular or above (by the acting member\'s stored ' \
                  'roles; the bot names it in `data.acting_user_id`) creates a Franchise IGDB doesn\'t have, ' \
                  'returning 201. With `igdb_franchise_id`, the admin/service find-or-create keyed on it (the ' \
                  'bot\'s `ensureFranchise`): the existing franchise with 200 when the IGDB id is already known, ' \
                  'or a new one with 201; `name` is applied only when a new row is created.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              name: { type: :string, maxLength: 255, description: 'Franchise name (set only on create).' },
              igdb_franchise_id: { type: :integer, description: 'IGDB franchise id: the upsert key. Leave it out ' \
                                                                 'to create a Franchise by hand.' },
              acting_user_id: { type: :string, description: 'Bot only, creating by hand: the member it acts for.' }
            },
            required: %w[name]
          }
        },
        required: %w[data]
      }

      response '201', 'franchise created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Franchise' } }
      end

      response '200', 'existing franchise (matched on IGDB id)' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/Franchise' } }
      end

      response '400', 'missing `data`, or the bot creating by hand names no acting member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: an upsert by a caller who is not an admin or the service, or a hand-made ' \
                      'Franchise by a member below Regular' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed (an empty `igdb_franchise_id`, or a blank or too-long `name`)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/franchises/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbFranchise id.'

    get 'Show franchise' do
      tags 'Franchises'
      description 'A Franchise\'s page: its columns, its games grouped as `mainline`, `other` and `add_ons` ' \
                  '(games with a parent game, under their parent when it is in GameDB), each with cover and ' \
                  'release year, oldest first, and `viewer` (what the acting member may change).'
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, schema: { type: :string }, required: false,
        description: 'Bot only: the member `viewer` is for.'

      response '200', 'franchise' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/FranchisePage' } }
      end

      response '404', 'franchise not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/franchises/{id}/games/{game_id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbFranchise id.'
    parameter name: :game_id, in: :path, schema: { type: :string }, required: true, description: 'GamedbGame id.'

    put 'Link a game to a franchise' do
      tags 'Franchises'
      description 'Regulars and above (the acting member\'s stored roles). Links the game as `manual` if it ' \
                  'isn\'t linked (forgetting an earlier unlink of the pair), and sets Mainline when `mainline` ' \
                  'is given. An existing link keeps its source. Hand links survive IGDB re-imports.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: false, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              mainline: { type: :boolean, description: 'Mark (true) or unmark (false) the game as Mainline; ' \
                                                        'leave out to keep it.' },
              acting_user_id: { type: :string, description: 'Bot only: the member it acts for.' }
            }
          }
        }
      }

      response '200', 'the link' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/FranchiseLink' } }
      end

      response '400', 'the bot names no acting member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: below Regular' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'franchise or game not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', '`mainline` is not a boolean (`invalid_mainline`)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Unlink a game from a franchise' do
      tags 'Franchises'
      description 'Regulars and above. Removes the link and remembers it, so an IGDB re-import doesn\'t add it ' \
                  'back. Succeeds also when the game wasn\'t linked.'
      parameter name: :acting_user_id, in: :query, schema: { type: :string }, required: false,
        description: 'Bot only: the member it acts for.'

      response '204', 'unlinked' do
      end

      response '400', 'the bot names no acting member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: below Regular' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'franchise or game not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
