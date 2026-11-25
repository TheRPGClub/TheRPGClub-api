# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/playtime', type: :request do
  playtime_response = {
    type: :object, properties: { data: { '$ref' => '#/components/schemas/GamePlaytime' } }, required: %w[data]
  }
  write_rule = 'Writes are the member\'s own; a Superadmin and the bot\'s service token may write for anyone ' \
               '(403 otherwise). Answers with the game\'s Playtime for that member, as ' \
               '`GET /users/{user_id}/games/{game_id}/playtime` does. Ungated.'

  path '/api/v1/users/{user_id}/games/{game_id}/playtime' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord user id of the member.'
    parameter name: :game_id, in: :path, schema: { type: :integer }, required: true, description: 'GameDB game id.'

    get 'Show a member\'s Playtime for a game' do
      tags 'Playtime'
      description 'The member\'s Playtime for the game (ADR 0015): the sum of every Provider figure ' \
                  '(Steam, RetroAchievements, PSN, from synced Achievement Sets mapped to the game; an unmapped ' \
                  'set counts for nothing) and every Manual Playtime entry. `breakdown` lists each Provider set ' \
                  'with its resolved platform (a label that doesn\'t resolve stays raw, with a null ' \
                  '`platform_id`) and each Manual entry. A Provider figure on a platform whose Manual entry ' \
                  'keeps over it is shown with `counted: false`. `mismatches` lists each platform where a ' \
                  'Manual entry and a Provider both report time with no keep chosen. `playthrough` is the ' \
                  'member\'s open Playthrough of the game (null when none is open) and `playthroughs` the ' \
                  'earlier ones, newest first. Open to any signed-in ' \
                  'caller; ungated. 404 for an unknown member or game.'
      produces 'application/json'

      response '200', 'the member\'s Playtime for the game' do
        schema playtime_response
      end

      response '404', 'unknown member or game' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/users/{user_id}/games/{game_id}/playtime/mismatches' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord user id of the member.'
    parameter name: :game_id, in: :path, schema: { type: :integer }, required: true, description: 'GameDB game id.'

    post 'Settle a Playtime mismatch' do
      tags 'Playtime'
      description 'Settles the mismatch on `platform_id`. `keep: manual` ("keep mine") sets the Manual ' \
                  'entry\'s `keeps_over_provider` to the Provider reporting that platform, so that Provider\'s ' \
                  'figure there is shown but no longer counted. `keep: provider` deletes the Manual entry. ' \
                  '`keep: both` sets the Manual entry\'s `mismatch_acknowledged_provider` to that Provider: both ' \
                  'figures keep counting (ADR 0015) and the pair is no longer reported as a mismatch; another ' \
                  'Provider on the platform still is, and moving the entry to another platform clears it. ' \
                  '422 `no_mismatch` when the platform has none, `invalid_keep` for another `keep`. ' + write_rule
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              platform_id: { type: :integer, description: 'The mismatch\'s GameDB platform.' },
              keep: { type: :string, enum: %w[manual provider both] }
            },
            required: %w[platform_id keep]
          }
        },
        required: %w[data]
      }

      response '200', 'settled; the game\'s Playtime' do
        schema playtime_response
      end

      response '422', '`no_mismatch` or `invalid_keep`' do
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

  path '/api/v1/users/{user_id}/games/{game_id}/manual_playtimes' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord user id of the member.'
    parameter name: :game_id, in: :path, schema: { type: :integer }, required: true, description: 'GameDB game id.'

    post 'Add or set Manual Playtime' do
      tags 'Playtime'
      description 'Creates or changes the member\'s Manual Playtime entry for the game on `platform_id` (null ' \
                  'is "Other"; one entry per platform). `mode: add` (the default) raises its minutes, ' \
                  '`mode: set` replaces them. `note` replaces the note; leaving it out keeps it. 422 ' \
                  '`invalid_mode`, `invalid_minutes` (not a whole number of 0 or more) or `unknown_platform`, ' \
                  'and 422 for a note over 280 characters. ' + write_rule
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              platform_id: { type: :integer, nullable: true, description: 'GameDB platform; null is "Other".' },
              minutes: { type: :integer, minimum: 0, description: 'Minutes to add, or the new total.' },
              mode: { type: :string, enum: %w[add set], default: 'add' },
              note: { type: :string, nullable: true, maxLength: 280 }
            },
            required: %w[minutes]
          }
        },
        required: %w[data]
      }

      response '200', 'saved; the game\'s Playtime' do
        schema playtime_response
      end

      response '422', 'invalid mode, minutes, platform or note' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: not the member, a Superadmin or the bot' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'unknown member or game' do
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

  path '/api/v1/manual_playtimes/{id}' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true, description: 'Manual entry id.'

    patch 'Change a Manual Playtime entry' do
      tags 'Playtime'
      description 'Changes the entry\'s `minutes` (the new total), `note` or `platform_id` (null is "Other"), ' \
                  'each optional. Moving it to another platform clears its `keeps_over_provider` and ' \
                  '`mismatch_acknowledged_provider`; a platform ' \
                  'that already has an entry is 422. ' + write_rule
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              minutes: { type: :integer, minimum: 0 },
              note: { type: :string, nullable: true, maxLength: 280 },
              platform_id: { type: :integer, nullable: true }
            }
          }
        },
        required: %w[data]
      }

      response '200', 'saved; the game\'s Playtime' do
        schema playtime_response
      end

      response '422', 'invalid minutes, platform or note, or the platform already has an entry' do
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

    delete 'Delete a Manual Playtime entry' do
      tags 'Playtime'
      description 'Deletes the entry (seeded ones too). ' + write_rule
      produces 'application/json'

      response '200', 'deleted; the game\'s Playtime' do
        schema playtime_response
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
