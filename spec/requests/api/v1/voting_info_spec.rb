# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/voting_info', type: :request do
  # The client-writable BotVotingInfo columns. `round_number` is the
  # client-supplied primary key.
  writable = {
    round_number: { type: :integer, description: 'Voting round number (primary key). Required on create.' },
    next_vote_at: { type: :string, format: 'date-time', description: 'When the next vote opens. Required on create.' },
    nomination_list_id: { type: :integer, nullable: true, description: 'Optional nomination list id.' },
    five_day_reminder_sent: { type: :boolean, description: 'Whether the 5-day reminder fired. Optional; defaults to false.' },
    one_day_reminder_sent: { type: :boolean, description: 'Whether the 1-day reminder fired. Optional; defaults to false.' }
  }

  path '/api/v1/voting_info' do
    get 'List voting info rounds' do
      tags 'Voting Info'
      description 'Returns bot-managed voting metadata, newest round first. Open to any authenticated caller.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'voting info list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/VotingInfo' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create voting info' do
      tags 'Voting Info'
      description 'Open to any authenticated caller. `round_number` (the PK) and `next_vote_at` are ' \
                  'required; the reminder flags default to false.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[round_number next_vote_at] } },
        required: %w[data]
      }

      response '201', 'voting info created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/VotingInfo' } }
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/voting_info/current' do
    get 'Show the current voting info round' do
      tags 'Voting Info'
      description 'Returns the current round (the row with the highest `round_number`), or 404 if no ' \
                  'rounds exist. Lets the bot read the newest round without fetching the full list. ' \
                  'Open to any authenticated caller.'
      produces 'application/json'

      response '200', 'current voting info' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/VotingInfo' } }
      end

      response '404', 'no voting info rounds exist' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/voting_info/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'BotVotingInfo round_number.'

    get 'Show voting info' do
      tags 'Voting Info'
      produces 'application/json'

      response '200', 'voting info detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/VotingInfo' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update voting info' do
      tags 'Voting Info'
      description 'Partial update: send any subset of the writable columns.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/VotingInfo' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    put 'Replace voting info (alias)' do
      tags 'Voting Info'
      description 'Alias for PATCH (applied as a partial assign).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/VotingInfo' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete voting info' do
      tags 'Voting Info'
      produces 'application/json'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedResponse'
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
