# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/steam_app_gamedb_maps', type: :request do
  writable = {
    steam_app_id: { type: :integer, description: 'Steam appid (the upsert key). Required.' },
    gamedb_game_id: { type: :integer, nullable: true, description: 'The matched gamedb_games.game_id.' },
    status: { type: :string, enum: %w[mapped skipped], description: 'Required.' },
    created_by: { type: :string, nullable: true, description: 'Discord user_id of the caller who resolved this mapping.' }
  }

  path '/api/v1/steam_app_gamedb_maps/{steam_app_id}' do
    parameter name: :steam_app_id, in: :path, schema: { type: :integer }, required: true,
              description: 'Steam appid.'

    get 'Show a Steam app -> GameDB game mapping' do
      tags 'Steam App GameDB Maps'
      description 'Open to any authenticated caller.'
      produces 'application/json'

      response '200', 'mapping' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SteamAppGamedbMap' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/steam_app_gamedb_maps' do
    post 'Upsert a Steam app -> GameDB game mapping' do
      tags 'Steam App GameDB Maps'
      description 'Admin-or-service-only. Inserts or updates a mapping keyed on steam_app_id, so a ' \
                  "repeated Steam app doesn't need to be re-resolved by the bot's matcher. " \
                  'Returns 201 on insert, 200 on update.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[steam_app_id status] } },
        required: %w[data]
      }

      response '201', 'mapping created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SteamAppGamedbMap' } }
      end

      response '200', 'mapping updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/SteamAppGamedbMap' } }
      end

      response '403', 'forbidden — caller is not admin or service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing steam_app_id' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/users/{user_id}/steam_app_gamedb_maps/historical' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
              description: 'Discord user_id.'

    get "Get a user's historically-mapped GameDB game ids" do
      tags 'Steam App GameDB Maps'
      description "The distinct gamedb_game_ids this user has previously mapped a Steam app to " \
                  "(status: mapped), so the bot can bias fuzzy matching toward games the user already owns. " \
                  'Open to any authenticated caller.'
      produces 'application/json'

      response '200', 'game ids' do
        schema type: :object, properties: { data: { type: :array, items: { type: :integer } } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
