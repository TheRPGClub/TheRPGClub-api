# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/playthroughs', type: :request do
  playtime_response = {
    type: :object, properties: { data: { '$ref' => '#/components/schemas/GamePlaytime' } }, required: %w[data]
  }
  write_rule = 'Writes are the member\'s own; a Superadmin and the bot\'s service token may write for anyone ' \
               '(403 otherwise). Answers with the game\'s Playtime for that member, as ' \
               '`GET /users/{user_id}/games/{game_id}/playtime` does, with the Playthrough in `playthrough` ' \
               '(open) or `playthroughs` (ended). Ungated.'

  path '/api/v1/users/{user_id}/games/{game_id}/playthroughs' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord user id of the member.'
    parameter name: :game_id, in: :path, schema: { type: :integer }, required: true, description: 'GameDB game id.'

    post 'Start a Playthrough' do
      tags 'Playtime'
      description 'Starts a Playthrough of the game: one run, measured as the Playtime gained from now on ' \
                  '(the member\'s Playtime now is its baseline), Manual Playtime added while it is open ' \
                  'included, floored at 0. At most one is open per member and game: 409 `playthrough_open` ' \
                  'while one is. Adding the game to Now Playing also opens one; a Game Completion of the game ' \
                  'closes it. ' + write_rule
      produces 'application/json'

      response '201', 'started; the game\'s Playtime' do
        schema playtime_response
      end

      response '409', '`playthrough_open`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: not the member, a Superadmin or the bot' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'unknown member or game' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/playthroughs/{id}' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true, description: 'Playthrough id.'

    patch 'Set a Playthrough\'s total' do
      tags 'Playtime'
      description 'Sets the open Playthrough\'s time by hand ("this one took 45 h"), replacing the measured ' \
                  'time; `total_minutes: null` goes back to the measured time. 422 `invalid_total_minutes` ' \
                  'when it is missing or not a whole number of 0 or more; 409 `playthrough_closed` once it ' \
                  'has ended. ' + write_rule
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              total_minutes: { type: :integer, minimum: 0, nullable: true,
                               description: 'The Playthrough\'s time; null for the measured time.' }
            },
            required: %w[total_minutes]
          }
        },
        required: %w[data]
      }

      response '200', 'saved; the game\'s Playtime' do
        schema playtime_response
      end

      response '422', '`invalid_total_minutes`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', '`playthrough_closed`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: not the member, a Superadmin or the bot' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing `data` parameter' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/playthroughs/{id}/abandon' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true, description: 'Playthrough id.'

    post 'Abandon a Playthrough' do
      tags 'Playtime'
      description 'Ends the open Playthrough as `abandoned`, keeping the time it had. 409 ' \
                  '`playthrough_closed` once it has ended. ' + write_rule
      produces 'application/json'

      response '200', 'abandoned; the game\'s Playtime' do
        schema playtime_response
      end

      response '409', '`playthrough_closed`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: not the member, a Superadmin or the bot' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
