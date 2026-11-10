# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/achievements highlights', type: :request do
  path '/api/v1/achievements/highlights/pending' do
    get 'List pending Achievement Highlights' do
      tags 'Achievement Hub'
      description 'Service only. Announceable Unlocks (Highlights found by an incremental sync within 48h of ' \
                  'their `unlocked_at`) not yet acked, oldest id first, at most 25. Departed members are ' \
                  'excluded. Post them, then ack the ids posted (or skipped as permanently failing) with ' \
                  '`POST /achievements/highlights/ack`. Mask a `hidden` Achievement. `alerts` carries the PSN ' \
                  'auth alert: post it while `psn_auth_expired_at` is set and `psn_auth_alerted` is false, then ' \
                  'ack it. `data` is empty while the Achievement Hub is Off; the held Highlights are listed once ' \
                  'it is back on.'
      produces 'application/json'

      response '200', 'pending Highlights and alerts' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/AchievementHighlight' } },
          alerts: { '$ref' => '#/components/schemas/AchievementHubAlerts' }
        }, required: %w[data alerts]
      end

      response '403', 'not the service' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/achievements/highlights/ack' do
    post 'Acknowledge posted Achievement Highlights' do
      tags 'Achievement Hub'
      description 'Service only. Marks the given Unlocks announced, so they leave the pending list. ' \
                  'Idempotent (an Unlock keeps its first ack time); ids that are not announceable are ignored. ' \
                  'The response lists the given ids that are now announced.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              ids: { type: :array, maxItems: Achievements::HighlightOutbox::MAX_ACK,
                     items: { type: :integer, minimum: 1 } }
            },
            required: %w[ids]
          }
        },
        required: %w[data]
      }

      response '200', 'Highlights acknowledged' do
        schema type: :object, properties: {
          data: {
            type: :object,
            properties: { ids: { type: :array, items: { type: :integer } } },
            required: %w[ids]
          }
        }, required: %w[data]
      end

      response '403', 'not the service' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'missing or malformed ids' do
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
