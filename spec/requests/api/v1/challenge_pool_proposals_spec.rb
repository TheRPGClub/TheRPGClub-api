# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/challenge_pool_proposals', type: :request do
  one_proposal = { type: :object, properties: { data: { '$ref' => '#/components/schemas/ChallengePoolProposal' } } }
  deciders = "The Host, or any Moderator or above (403 \"Only the Host or a Moderator can accept or decline Pool Proposals.\" otherwise)."

  path '/api/v1/challenges/{challenge_id}/pool_proposals' do
    parameter name: :challenge_id, in: :path, schema: { type: :integer }, required: true

    get 'List Pool Proposals' do
      tags 'Challenges'
      description 'Members (the `challenges` Feature) who can see the Challenge. Newest first. Those who decide ' \
                  '(the Host and Moderators and above) see every proposal; other members see their own. ' \
                  'The bot names the member it reads for with `acting_user_id`.'
      produces 'application/json'
      parameter name: :status, in: :query, required: false, schema: { type: :string, enum: ChallengePoolProposal::STATUSES }
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'Pool Proposals' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/ChallengePoolProposal' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '400', 'an unknown `status`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no Challenge the member can see' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Propose a game for a Pool' do
      tags 'Challenges'
      description 'Any member who can see the Pool Challenge. 409 `already_in_pool` when the game is a Core or ' \
                  'Optional Game already (through a source too); 409 `already_proposed` (with `proposal_id`) ' \
                  'when it is pending already, whoever proposed it. An excluded game may be proposed. 422 ' \
                  '`not_pool` for a Slots or Assignment Challenge, 422 `invalid_proposal` for an unknown game ' \
                  'or a note over 280 characters. Queues a `challenge_dm` `pool_proposal` for the Host when they ' \
                  'keep Challenge DMs on and didn\'t propose it; for a club-hosted Challenge, one `pool_proposal` ' \
                  'with `club_hosted: true` and no `user_id`, for the bot to post in #dev.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object, required: %w[data], properties: {
          data: { type: :object, required: %w[game_id], properties: {
            game_id: { type: :integer },
            note: { type: :string, maxLength: ChallengePoolProposal::NOTE_MAX, nullable: true,
                    description: 'Optional: why, for whoever decides.' },
            acting_user_id: { type: :string, description: 'Service only, required.' }
          } }
        }
      }

      response '201', 'the pending proposal' do
        schema one_proposal
      end

      response '404', 'no Challenge the member can see' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'already_in_pool or already_proposed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'not_pool or invalid_proposal' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/challenges/{challenge_id}/pool_proposals/{id}/accept' do
    parameter name: :challenge_id, in: :path, schema: { type: :integer }, required: true
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    post 'Accept a Pool Proposal' do
      tags 'Challenges'
      description "#{deciders} Puts the game in the Pool as a Core or Optional Game (picked by hand), lifting " \
                  'an exclusion, as a Pool edit would: Runs are brought up to date, and a new Core Game queues ' \
                  '`pool_goal_changed` DMs. Queues a `challenge_dm` `pool_proposal_accepted` for the proposer ' \
                  'when they keep Challenge DMs on and didn\'t accept it themselves. With `add_to_list`, the game ' \
                  'also goes into the linked Game List (403 "Only the Game List\'s owner can add games to it ' \
                  'from this Challenge." unless ' \
                  '`pool.game_list.can_add`; 422 `invalid_challenge` without a linked list, 422 `list_full`). 409 ' \
                  '`already_decided`; 422 `invalid_proposal` for an `as` other than core or optional.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object, required: %w[data], properties: {
          data: { type: :object, required: %w[as], properties: {
            as: { type: :string, enum: ChallengePoolProposal::ACCEPTED_AS },
            add_to_list: { type: :boolean, description: 'Also add the game to the linked Game List.' },
            acting_user_id: { type: :string, description: 'Service only, required.' }
          } }
        }
      }

      response '200', 'the accepted proposal' do
        schema one_proposal
      end

      response '403', 'not a decider, or `add_to_list` from someone who may not touch the list' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'already_decided' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'invalid_proposal, invalid_challenge or list_full' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/challenges/{challenge_id}/pool_proposals/{id}/decline' do
    parameter name: :challenge_id, in: :path, schema: { type: :integer }, required: true
    parameter name: :id, in: :path, schema: { type: :integer }, required: true

    post 'Decline a Pool Proposal' do
      tags 'Challenges'
      description "#{deciders} Leaves the Pool alone and sends no DM; the game may be proposed again. 409 " \
                  '`already_decided`. The bot sends `{ "data": { "acting_user_id": "..." } }`.'
      produces 'application/json'

      response '200', 'the declined proposal' do
        schema one_proposal
      end

      response '403', 'not a decider' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'already_decided' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
