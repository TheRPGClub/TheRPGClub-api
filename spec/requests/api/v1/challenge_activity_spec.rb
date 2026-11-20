# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/challenge_activity', type: :request do
  path '/api/v1/challenge_activity' do
    get 'List recent Challenge Activity' do
      tags 'Challenges'
      description 'Members (the `challenges` Feature). Recent Challenge happenings club-wide, for the ' \
                  "dashboard's Challenge Activity panel: Runs started, games Cleared on a Run, Runs Finished, " \
                  "and Secret Santa sign-ups opening and reveals. Derived from what Runs and Editions store, so " \
                  'a deleted Run or Challenge takes its events with it. Hidden Challenges are left out for ' \
                  'everyone, staff included. Newest first: by `occurred_on`, then `occurred_at`, where an event ' \
                  'known only by its date sorts as the start of its club day. One page of `per` events.'
      produces 'application/json'
      parameter name: :per, in: :query, schema: { type: :integer, default: 10, maximum: 50 }, required: false

      response '200', 'events' do
        schema type: :object, required: %w[data meta], properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/ChallengeActivityEvent' } },
          meta: { type: :object, required: %w[per], properties: { per: { type: :integer } } }
        }
      end

      response '404', 'the caller cannot use the `challenges` Feature' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
