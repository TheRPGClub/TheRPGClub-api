# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/presence_prompts', type: :request do
  path '/api/v1/users/{user_id}/presence_prompts' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'List a user\'s presence prompt history' do
      tags 'Presence Prompts'
      description 'Read-only history of presence prompts the bot sent the user after detecting ' \
                  '(via Discord rich presence) that they were playing a game. Ordered newest first. ' \
                  'The bot owns all writes; the user-settable side is the opt-out preference.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'presence prompt history' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/PresencePrompt' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/users/{user_id}/presence_prompt_opts' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'Show a user\'s presence-prompt opt-out preference' do
      tags 'Presence Prompts'
      description 'The user\'s opt-out preference as a single document: `all` (whether every game is ' \
                  'silenced) plus the list of per-game opt-outs.'
      produces 'application/json'

      response '200', 'opt-out preference' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/PresencePromptOpts' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    put 'Replace a user\'s presence-prompt opt-out preference' do
      tags 'Presence Prompts'
      description 'Owner-only. Replaces the entire opt-out set. `all` toggles the silence-everything ' \
                  'opt-out; `games` lists titles to silence individually (normalized like the bot; ' \
                  'blanks and duplicates dropped). An empty or omitted set clears the opt-outs ' \
                  '(opt back in).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              all: { type: :boolean, description: 'Opt out of prompts for every game.' },
              games: {
                type: :array,
                items: { type: :string },
                description: 'Game titles to silence individually.'
              }
            }
          }
        },
        required: %w[data]
      }

      response '200', 'updated opt-out preference' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/PresencePromptOpts' } }
      end

      response '403', 'forbidden — caller is not the owner' do
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
end
