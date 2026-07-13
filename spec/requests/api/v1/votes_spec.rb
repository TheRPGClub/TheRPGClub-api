# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/votes', type: :request do
  # Caller-settable fields on a cast. `round_number` comes from the path;
  # `gamedb_game_id` and `voted_at` are derived server-side.
  writable = {
    user_id: { type: :string, description: 'Voter (Discord user id). Required. Service may name any user; a user session only their own id.' },
    nomination_id: { type: :integer, description: 'The nomination being voted on (must belong to the round in the path). Required.' }
  }

  cast_description =
    'Casts the user\'s vote on a nomination, or takes it back. Owner-gated: the service token may ' \
    'cast on behalf of any user, a user session only for themselves. Only allowed while the round\'s ' \
    'voting window is open (from `next_vote_at` until `vote_ends_at`, defaulting to the end of the ' \
    'following Sunday, US Eastern). Votes are per game: voting a game the user already voted takes ' \
    'that vote back (`action: unvoted`, 200) — even via a different nomination of the same game. ' \
    'Users hold at most `cap` votes per round (3 when the round has 9+ nominations, else 2); casting ' \
    'a new game at the cap evicts their oldest vote(s), reported in `removed_votes` with a `warning` ' \
    'to surface to the voter. 201 when a vote was placed.'

  list_description =
    'The round\'s votes with voter identities, oldest first. Votes are anonymous while the voting ' \
    'window is open: until voting has ended this list is admin/service-only (403 otherwise). Use ' \
    'the tally for anonymous counts.'

  tally_description =
    'Anonymous vote counts per nomination, most-voted first. Open to any authenticated caller at ' \
    'any time — no voter identities. Nominations with zero votes have no row; merge against the ' \
    'round\'s nominations list. `meta.cap` is the per-user vote cap for the round (3 when the ' \
    'round has 9+ nominations, else 2), for rendering "vote for up to N".'

  user_votes_description =
    'One voter\'s votes for the round, oldest first (an empty array when they have none — never ' \
    '404). While the voting window is open this is limited to the voter themselves and ' \
    'admin/service; once voting has ended it opens to any authenticated caller.'

  destroy_description =
    'Admin/service-only. Clears every vote for the round (the reset alongside the nominations one).'

  identified_list_schema = {
    type: :object,
    properties: {
      data: { type: :array, items: { '$ref' => '#/components/schemas/Vote' } },
      meta: { '$ref' => '#/components/schemas/PaginationMeta' }
    }
  }

  [
    [ 'GOTM', 'gotm_entries' ],
    [ 'Non-RPG GOTM', 'nr_gotm_entries' ]
  ].each do |label, entries_path|
    path "/api/v1/#{entries_path}/{round}/votes" do
      parameter name: :round, in: :path, schema: { type: :integer }, required: true,
        description: "#{label} voting round number."

      get "List #{label} votes for a round (identified)" do
        tags 'GOTM'
        description list_description
        produces 'application/json'
        parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
        parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

        response '200', "#{label} votes" do
          schema identified_list_schema
        end

        response '403', 'forbidden — voting is still open and the caller is not admin/service' do
          schema '$ref' => '#/components/schemas/Error'
        end

        response '401', 'unauthenticated' do
          schema '$ref' => '#/components/schemas/Error'
        end
      end

      post "Cast or toggle a #{label} vote" do
        tags 'GOTM'
        description cast_description
        consumes 'application/json'
        produces 'application/json'

        parameter name: :body, in: :body, required: true, schema: {
          type: :object,
          properties: { data: { type: :object, properties: writable, required: %w[user_id nomination_id] } },
          required: %w[data]
        }

        response '201', 'vote placed (`action: voted`; check `removed_votes`/`warning` for evictions)' do
          schema type: :object, properties: { data: { '$ref' => '#/components/schemas/VoteCastResult' } }
        end

        response '200', 'vote taken back (`action: unvoted` — the game was already voted)' do
          schema type: :object, properties: { data: { '$ref' => '#/components/schemas/VoteCastResult' } }
        end

        response '403', 'forbidden — caller is neither the named voter nor the service' do
          schema '$ref' => '#/components/schemas/Error'
        end

        response '404', '`nomination_not_found` — no such nomination in this round' do
          schema '$ref' => '#/components/schemas/Error'
        end

        response '422', '`voting_closed` (outside the voting window) or `nomination_missing_game`' do
          schema '$ref' => '#/components/schemas/Error'
        end

        response '400', 'missing `data` parameter' do
          schema '$ref' => '#/components/schemas/Error'
        end

        response '401', 'unauthenticated' do
          schema '$ref' => '#/components/schemas/Error'
        end
      end

      delete "Delete all #{label} votes for a round" do
        tags 'GOTM'
        description destroy_description
        produces 'application/json'

        response '200', 'deleted' do
          schema '$ref' => '#/components/schemas/DeletedCountResponse'
        end

        response '403', 'forbidden — caller is not an admin or service' do
          schema '$ref' => '#/components/schemas/Error'
        end

        response '401', 'unauthenticated' do
          schema '$ref' => '#/components/schemas/Error'
        end
      end
    end

    path "/api/v1/#{entries_path}/{round}/votes/tally" do
      parameter name: :round, in: :path, schema: { type: :integer }, required: true,
        description: "#{label} voting round number."

      get "Tally #{label} votes for a round (anonymous)" do
        tags 'GOTM'
        description tally_description
        produces 'application/json'

        response '200', 'vote counts per nomination' do
          schema type: :object, properties: {
            data: { type: :array, items: { '$ref' => '#/components/schemas/VoteTally' } },
            meta: {
              type: :object,
              properties: { cap: { type: :integer, description: 'Per-user vote cap for this round.' } },
              required: %w[cap]
            }
          }
        end

        response '401', 'unauthenticated' do
          schema '$ref' => '#/components/schemas/Error'
        end
      end
    end

    path "/api/v1/#{entries_path}/{round}/votes/{user_id}" do
      parameter name: :round, in: :path, schema: { type: :integer }, required: true,
        description: "#{label} voting round number."
      parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
        description: 'Voter (Discord user id).'

      get "Show a user's #{label} votes for a round" do
        tags 'GOTM'
        description user_votes_description
        produces 'application/json'

        response '200', 'the user\'s votes' do
          schema type: :object, properties: {
            data: { type: :array, items: { '$ref' => '#/components/schemas/Vote' } }
          }
        end

        response '403', 'forbidden — voting is still open and the caller is neither the voter nor admin/service' do
          schema '$ref' => '#/components/schemas/Error'
        end

        response '401', 'unauthenticated' do
          schema '$ref' => '#/components/schemas/Error'
        end
      end
    end
  end
end
