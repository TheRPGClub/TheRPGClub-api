# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/challenge_editions', type: :request do
  one_edition = { type: :object, properties: { data: { '$ref' => '#/components/schemas/ChallengeEdition' } } }
  editions = 'An Edition is one yearly cycle of an Assignment (Secret Santa) Challenge, named by the year of its ' \
             'reveal. It opens by itself the day after the previous reveal (the first one, when the Challenge is ' \
             'created), takes sign-ups until the start of its cutoff day, and is then drawn: members with fewer ' \
             'than 5 games in their backlog are left out, the rest go round one random circle and get a Run ' \
             'each, and with fewer than 2 the Edition is cancelled. Santas pick until the start of the pick ' \
             'deadline day; at the deadline the others get a random pick. On the reveal date `assignments` lists ' \
             'every game picked, and the Edition ends on the next reveal date, when unFinished Runs Expire. ' \
             'Dates are the club\'s (America/New_York). A Santa is served to nobody but staff (Moderators and ' \
             'above, who also see `assignments` from the draw on) before the Edition ends.'
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
      description 'Takes the acting member off the Edition, before the cutoff. After the draw, until the start ' \
                  'of the pick deadline day, a drawn member withdraws instead: their pick is dropped (their ' \
                  'recipient gets a random one at the deadline; the circle is not redrawn), their own Run is ' \
                  'Abandoned, and they show as `withdrawn`. 409 `signup_closed` between the cutoff and the draw ' \
                  'and after the Edition is cancelled, 409 `picks_closed` from the pick deadline on, 409 ' \
                  '`not_drawn` for a member the draw left out, 409 `not_signed_up`. The bot sends ' \
                  '`acting_user_id` as a query parameter.'
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }

      response '200', 'the Edition, without the member' do
        schema one_edition
      end

      response '404', 'not found, or hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'signup_closed, picks_closed, not_drawn or not_signed_up' do
        schema type: :object, properties: {
          error: { type: :string, enum: %w[signup_closed picks_closed not_drawn not_signed_up] },
          message: { type: :string }
        }
      end
    end
  end

  one_santa = { type: :object, properties: { data: { '$ref' => '#/components/schemas/ChallengeSanta' } } }
  not_a_santa = 'not_a_santa: the acting member is not a Santa in this Edition (not drawn yet, never drawn, or ' \
                'withdrew)'

  path '/api/v1/challenge_editions/{id}/santa' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    get "Show the acting member's side as a Santa" do
      tags 'Challenges'
      description 'The Santa\'s view, only for the Santa: their recipient, their pick, the deadline, and the ' \
                  'recipient\'s backlog minus the games they have Cleared, which `q` narrows by title. The bot ' \
                  'sends `acting_user_id` as a query parameter (400 without).'
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }
      parameter name: :q, in: :query, required: false, schema: { type: :string }

      response '200', "the Santa's view" do
        schema one_santa
      end

      response '403', not_a_santa do
        schema type: :object, properties: { error: { type: :string, enum: %w[not_a_santa] }, message: { type: :string } }
      end

      response '404', 'not found, or hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/challenge_editions/{id}/santa/pick' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    put "Pick the recipient's game" do
      tags 'Challenges'
      description 'Records (or changes) the acting Santa\'s pick, a game in their recipient\'s backlog that ' \
                  'the recipient hasn\'t Cleared, until the start of the pick deadline day. It is revealed on the ' \
                  'reveal date and becomes the recipient\'s Run goal, even if it later leaves their backlog. ' \
                  'The bot adds `acting_user_id` to `data`.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object, required: %w[data], properties: { data: { type: :object, required: %w[game_id], properties: {
          game_id: { type: :integer }, acting_user_id: { type: :string }
        } } }
      }

      response '200', "the Santa's view, with the pick" do
        schema one_santa
      end

      response '400', 'game_id is not a whole number' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', not_a_santa do
        schema type: :object, properties: { error: { type: :string, enum: %w[not_a_santa] }, message: { type: :string } }
      end

      response '404', 'not found, or hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'picks_closed: from the start of the pick deadline day' do
        schema type: :object, properties: { error: { type: :string, enum: %w[picks_closed] }, message: { type: :string } }
      end

      response '422', "not_eligible: not in the recipient's backlog, or Cleared by them" do
        schema type: :object, properties: { error: { type: :string, enum: %w[not_eligible] }, message: { type: :string } }
      end
    end
  end
end
