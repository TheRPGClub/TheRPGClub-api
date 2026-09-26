# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/voting_events', type: :request do
  path '/api/v1/voting_events/claim' do
    post 'Claim due voting events' do
      tags 'Voting Events'
      description 'Service only. Leases up to `limit` due, unexpired, undelivered events (oldest first) for five ' \
                  'minutes: post each to Discord, then ack it. An unacked event is handed out again once its ' \
                  'lease runs out, so delivery is at-least-once.'
      produces 'application/json'
      parameter name: :limit, in: :query, schema: { type: :integer, default: 10, minimum: 1, maximum: 50 },
        required: false

      response '200', 'claimed events' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/VotingEvent' } }
        }
      end

      response '403', 'not the service' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/voting_events/{id}/ack' do
    parameter name: :id, in: :path, type: :integer

    post 'Acknowledge a delivered voting event' do
      tags 'Voting Events'
      description 'Service only. Marks the event delivered; idempotent.'
      produces 'application/json'

      response '200', 'event acknowledged' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/VotingEvent' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
