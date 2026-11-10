# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/features', type: :request do
  staff_rule = 'Admins and Superadmins only. A member signs in with their session. The bot calls with the ' \
               'service token and names the acting Discord user (`acting_user_id`); the same rule then ' \
               "applies to that member's stored roles (Admin, or the dev role for Superadmin), never to the " \
               'token. Moderators, members and a Discord user with no member record get 403.'

  path '/api/v1/features' do
    get 'List every Feature with its Feature Flag' do
      tags 'Features'
      description 'Every Feature in registry order with its Feature Flag state (off, preview, live), whether ' \
                  'it is Core or hideable, what it covers on the website, in the bot and in automated posts, ' \
                  "and its last change. #{staff_rule}"
      produces 'application/json'

      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string },
        description: 'Bot (service token) only, and then required: the Discord user acting through the bot.'

      response '200', 'every Feature' do
        schema type: :object,
          properties: { data: { type: :array, items: { '$ref' => '#/components/schemas/FeatureFlagEntry' } } },
          required: %w[data]
      end

      response '400', 'the bot did not name the acting Discord user' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: not an Admin or Superadmin' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/features/{key}' do
    parameter name: :key, in: :path, required: true, schema: { type: :string, enum: Features.keys },
      description: 'The Feature key.'

    patch "Set a Feature's Feature Flag" do
      tags 'Features'
      description 'Sets the Feature Off, Preview or Live, with an optional reason. Each change is written to the ' \
                  'change log (who, from, to, reason, when) and enqueues a `feature_flag_changed` bot job that ' \
                  'the bot posts in the admin channel. Its payload: `{ key, name, from_state, to_state, ' \
                  'changed_by, changed_by_name, reason }` (no `feature_key`: it is not routed by the Feature\'s ' \
                  'state). Setting the state the Feature already has (a Feature with no stored state reads as ' \
                  'preview) changes, logs and announces nothing and answers `meta.changed: false`. Leaving Off ' \
                  "for Achievement Hub starts achievement sync at once. #{staff_rule}"
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              state: { type: :string, enum: Features::STATES },
              reason: { type: :string, maxLength: Features::ChangeFlag::REASON_MAX, nullable: true,
                        description: 'Why, shown on the desk and in the announcement.' },
              acting_user_id: { type: :string,
                                description: 'Bot (service token) only, and then required: the Discord user ' \
                                             'acting through the bot. Logged as the changer.' }
            },
            required: %w[state]
          }
        },
        required: %w[data]
      }

      response '200', "the Feature's entry after the change" do
        schema type: :object,
          properties: {
            data: { '$ref' => '#/components/schemas/FeatureFlagEntry' },
            meta: {
              type: :object,
              properties: { changed: { type: :boolean, description: 'False when the Feature already had that state.' } },
              required: %w[changed]
            }
          },
          required: %w[data meta]
      end

      response '400', 'missing `data`, or the bot did not name the acting Discord user' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: not an Admin or Superadmin' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not a Feature' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'invalid or missing `state`, or `reason` too long' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
