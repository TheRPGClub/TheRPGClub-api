# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/achievements highlights', type: :request do
  path '/api/v1/achievements/highlights/pending' do
    get 'List pending Achievement Highlights' do
      tags 'Achievement Hub'
      description 'Service only. Announceable Unlocks (Highlights found by an incremental sync within 48h of ' \
                  'their `unlocked_at`) with an id past the stored cursor, oldest first, at most 25. Departed ' \
                  'members are excluded. Post them, then ack `meta.next_cursor`. `alerts` carries the PSN auth ' \
                  'alert: post it while `psn_auth_expired_at` is set and `psn_auth_alerted` is false, then ack it.'
      produces 'application/json'

      response '200', 'pending Highlights and alerts' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/AchievementHighlight' } },
          meta: {
            type: :object,
            properties: {
              cursor: { type: :integer, description: 'The stored cursor (0 when unset).' },
              next_cursor: { type: :integer, nullable: true,
                             description: 'The id of the last listed Unlock; null when nothing is pending.' }
            },
            required: %w[cursor next_cursor]
          },
          alerts: { '$ref' => '#/components/schemas/AchievementHubAlerts' }
        }, required: %w[data meta alerts]
      end

      response '403', 'not the service' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/achievements/highlights/ack' do
    post 'Acknowledge posted Achievement Highlights' do
      tags 'Achievement Hub'
      description 'Service only. Stores the cursor: the id of the last Unlock posted. The cursor only moves ' \
                  'forward, so a stale ack is a no-op; the response carries the stored cursor.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object, properties: { cursor: { type: :integer, minimum: 0 } }, required: %w[cursor]
      }

      response '200', 'cursor stored' do
        schema type: :object, properties: {
          data: { type: :object, properties: { cursor: { type: :integer } }, required: %w[cursor] }
        }
      end

      response '403', 'not the service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'missing or malformed cursor' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/achievements/alerts/ack' do
    post 'Acknowledge a posted Achievement Hub alert' do
      tags 'Achievement Hub'
      description 'Service only. Marks the alert as posted, once per expiry: a new `psn_auth_expired_at` ' \
                  're-arms it. A no-op while PSN auth is healthy. Returns the alerts after the ack.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { alert: { type: :string, enum: Achievements::HighlightOutbox::ALERTS } },
        required: %w[alert]
      }

      response '200', 'alert acknowledged' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/AchievementHubAlerts' } }
      end

      response '403', 'not the service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'unknown alert' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
