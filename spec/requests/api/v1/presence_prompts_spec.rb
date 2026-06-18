# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/presence_prompts', type: :request do
  # Lifecycle states a prompt moves through, mirroring the bot.
  statuses = %w[PENDING ACCEPTED DECLINED OPT_OUT_GAME OPT_OUT_ALL]

  path '/api/v1/users/{user_id}/presence_prompts' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'List a user\'s presence prompt history' do
      tags 'Presence Prompts'
      description 'Read-only history of presence prompts the bot sent the user after detecting ' \
                  '(via Discord rich presence) that they were playing a game. Ordered newest first. ' \
                  'The bot owns all writes; the user-settable side is the opt-out preference. ' \
                  'The optional `game_title_norm` and `status` filters back the bot\'s lookups: pass ' \
                  '`game_title_norm` with `per=1` for the last prompt date of a game, or combine with ' \
                  '`status=pending` and read `meta.count` for the pending counts.'
      produces 'application/json'
      parameter name: :game_title_norm, in: :query, schema: { type: :string }, required: false,
                description: 'Filter to a single normalized game title (matches the bot\'s normalization).'
      parameter name: :status, in: :query, schema: { type: :string, enum: statuses }, required: false,
                description: 'Filter by lifecycle status. Case-insensitive (`pending` and `PENDING` both match).'
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

    post 'Create a presence prompt' do
      tags 'Presence Prompts'
      description 'Service-only. Records a new prompt the bot just sent. `prompt_id` is the Discord ' \
                  'interaction/message id used to correlate the later resolution. The row starts ' \
                  '`PENDING` with a server-stamped `created_at`; `status`/`resolved_at` are ignored if sent.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              prompt_id: { type: :string, description: 'Discord interaction/message id (primary key).' },
              game_title: { type: :string, description: 'The detected game title.' },
              game_title_norm: { type: :string, description: 'Normalized game title (matches the bot\'s normalization).' }
            },
            required: %w[prompt_id game_title game_title_norm]
          }
        },
        required: %w[data]
      }

      response '201', 'prompt created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/PresencePrompt' } }
      end

      response '403', 'forbidden — service token required' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed' do
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

  path '/api/v1/presence_prompts/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true,
              description: 'The prompt_id (Discord interaction/message id).'

    patch 'Resolve a presence prompt' do
      tags 'Presence Prompts'
      description 'Service-only. Marks how the user resolved the prompt and stamps `resolved_at`. ' \
                  'Only `status` and `resolved_at` are writable; the prompt identity and game titles are immutable.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              status: { type: :string, enum: statuses, description: 'New lifecycle status.' },
              resolved_at: { type: :string, format: 'date-time', description: 'When the prompt was resolved.' }
            }
          }
        },
        required: %w[data]
      }

      response '200', 'prompt resolved' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/PresencePrompt' } }
      end

      response '403', 'forbidden — service token required' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed' do
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
