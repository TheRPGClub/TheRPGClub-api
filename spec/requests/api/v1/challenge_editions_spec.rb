# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/challenge_editions', type: :request do
  one_edition = { type: :object, properties: { data: { '$ref' => '#/components/schemas/ChallengeEdition' } } }
  editions = 'An Edition is one yearly cycle of an Assignment (Secret Santa) Challenge, named by the year of its ' \
             'reveal. It opens by itself the day after the previous reveal (the first one, when the Challenge is ' \
             'created), takes sign-ups until the start of its cutoff day, and is then drawn: members with fewer ' \
             'than 5 games in their backlog are left out, the rest go round one random circle and get a Run ' \
             'each, and with fewer than 2 the Edition is cancelled. Dates are the club\'s (America/New_York). Who ' \
             'gives to whom is never served here.'
  hidden = 'Editions of a hidden Challenge are found only by Moderators and above and its Host.'

  path '/api/v1/challenges/{challenge_id}/editions' do
    parameter name: :challenge_id, in: :path, schema: { type: :integer }, required: true

    get "List a Challenge's Editions" do
      tags 'Challenges'
      description "Members (the `challenges` Feature). Newest first. #{editions} #{hidden} The bot may name the " \
                  'member it reads for with `acting_user_id` (for `signed_up`).'
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'Editions' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/ChallengeEdition' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '404', 'not found, or hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/challenge_editions/{id}' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    get 'Show an Edition' do
      tags 'Challenges'
      description "Members. #{editions} #{hidden}"
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }

      response '200', 'the Edition' do
        schema one_edition
      end

      response '404', 'not found, or hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/challenge_editions/{id}/signup' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    post 'Sign up for an Edition' do
      tags 'Challenges'
      description 'Signs the acting member up, before the cutoff. Refusals carry `{ error, message }` written for ' \
                  'members: 409 `signup_closed` from the cutoff on, 409 `already_signed_up`, and 422 ' \
                  '`backlog_too_small` (with `minimum` and `backlog_count`) with fewer than 5 games in their ' \
                  'backlog. The bot sends `{ "data": { "acting_user_id": "..." } }` (400 without; 403 ' \
                  '`feature_unavailable` when the Feature Flag hides the Feature from that member).'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: false, schema: {
        type: :object, properties: { data: { type: :object, properties: { acting_user_id: { type: :string } } } }
      }

      response '200', 'the Edition, with the member signed up' do
        schema one_edition
      end

      response '404', 'not found, or hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'signup_closed or already_signed_up' do
        schema type: :object, properties: {
          error: { type: :string, enum: %w[signup_closed already_signed_up] }, message: { type: :string }
        }
      end

      response '422', 'backlog_too_small' do
        schema type: :object, properties: {
          error: { type: :string, enum: %w[backlog_too_small] }, message: { type: :string },
          minimum: { type: :integer, example: 5 }, backlog_count: { type: :integer, example: 3 }
        }
      end
    end

    delete 'Withdraw from an Edition' do
      tags 'Challenges'
      description 'Takes the acting member off the Edition, before the cutoff: 409 `signup_closed` from the ' \
                  'cutoff on, 409 `not_signed_up`. The bot sends `acting_user_id` as a query parameter.'
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }

      response '200', 'the Edition, without the member' do
        schema one_edition
      end

      response '404', 'not found, or hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'signup_closed or not_signed_up' do
        schema type: :object, properties: {
          error: { type: :string, enum: %w[signup_closed not_signed_up] }, message: { type: :string }
        }
      end
    end
  end
end
