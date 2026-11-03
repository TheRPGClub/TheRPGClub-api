# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/game_keys', type: :request do
  path '/api/v1/game_keys' do
    get 'List available game keys' do
      tags 'Game Keys'
      description 'The unclaimed keys in the giveaway, ordered by game title ' \
                  '(case-insensitive) then key_id. Each key embeds its `game` ' \
                  '(name + cover/art/logo) when the title is linked to a ' \
                  'GamedbGame, else `game` is null and only `game_title` is set. ' \
                  'The secret `key_value` is never included here — it is revealed ' \
                  'only to the claimer on a successful claim.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'available game keys' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/GameKey' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Donate a game key' do
      tags 'Game Keys'
      description 'Owner-only: a Discord caller may only donate as themselves ' \
                  '(`donor_user_id` must be their own id); the bot service token ' \
                  'may donate on anyone\'s behalf. The claim fields are read-only ' \
                  'on donation. A member\'s donation queues a `giveaway_hub_refresh` ' \
                  'bot job (payload `{ reason: "donate", key_id }`); the service ' \
                  'token\'s does not.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            description: 'Key attributes. Required: `platform`, `key_value`, `donor_user_id`, plus ' \
                         '`game_title` OR `gamedb_game_id` (when only `gamedb_game_id` is given the ' \
                         'title is backfilled from that game). Optional: `donor_notify_on_claim`, ' \
                         '`region` (defaults to `Global`). ' \
                         'The PK/claim/timestamp columns are server-managed and ignored if sent.',
            properties: {
              game_title: { type: :string, description: 'Display label; backfilled from the linked game when omitted.' },
              gamedb_game_id: { type: :integer, nullable: true, description: 'Links the key to a GamedbGame for the embedded game card.' },
              platform: { type: :string },
              region: { type: :string, enum: RpgClubGameKey::REGIONS, default: RpgClubGameKey::DEFAULT_REGION,
                        description: 'Where the key redeems. Omitted or null stores `Global`.' },
              key_value: { type: :string, description: 'The key secret.' },
              donor_user_id: { type: :string },
              donor_notify_on_claim: { type: :boolean }
            },
            required: %w[platform key_value donor_user_id]
          }
        },
        required: %w[data]
      }

      response '201', 'key donated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GameKey' } }
      end

      response '403', 'forbidden — caller is not the named donor' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing `data` parameter' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/game_keys/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubGameKey key_id.'

    get 'Get a single game key' do
      tags 'Game Keys'
      description 'Returns one key with its secret `key_value` revealed. Because ' \
                  'the secret is exposed, access is restricted to those entitled ' \
                  'to the key: its donor, an admin, the bot service token, or the ' \
                  'user who has claimed it. An unclaimed key has no claimer, so ' \
                  '(beyond donor/admin/service) it cannot be read out-of-band to ' \
                  'bypass the claim flow; the listing endpoints never expose the ' \
                  'secret at all.'
      produces 'application/json'

      response '200', 'the game key, with `key_value` revealed' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GameKey' } }
      end

      response '403', 'forbidden — caller is not the donor, claimer, an admin, or the service token' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Revoke a game key' do
      tags 'Game Keys'
      description 'Revokes (deletes) a key. Restricted to the original donor, an ' \
                  'Admin, a Superadmin, or the bot service token. A member\'s revoke ' \
                  'queues a `giveaway_hub_refresh` bot job (payload ' \
                  '`{ reason: "revoke", key_id }`); the service token\'s does not.'
      produces 'application/json'

      response '200', 'key revoked' do
        schema type: :object, properties: { deleted: { type: :boolean } }, required: %w[deleted]
      end

      response '403', 'forbidden: caller is not the donor, an Admin, a Superadmin, or the service token' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/game_keys/{id}/claim' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubGameKey key_id.'

    post 'Claim a game key' do
      tags 'Game Keys'
      description 'Claims an unclaimed key and returns it with the secret ' \
                  '`key_value` revealed to the claimer. Requires the Discord ' \
                  'Members role (or the bot service token). The key row is locked, ' \
                  'so of two concurrent claims one wins and the other gets 409. ' \
                  'A Discord caller claims as themselves; the bot service token ' \
                  'claims on behalf of the `claimed_by_user_id` supplied in the body. ' \
                  'A member\'s claim queues two bot jobs: `giveaway_claim_notice` ' \
                  '(payload `{ key_id, claimed_by_user_id, donor_user_id, game_title, ' \
                  'platform }`; the bot DMs the key, logs the claim and notifies the ' \
                  'donor) and `giveaway_hub_refresh` (`{ reason: "claim", key_id }`). ' \
                  '`meta.claim_notice_job_id` is the notice job, for polling ' \
                  'GET /api/v1/bot_jobs/{id}. The service token\'s claims queue nothing.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: false, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            description: 'Service-token only: `claimed_by_user_id` names the Discord user ' \
                         'the claim is recorded for. Ignored for Discord callers (they claim ' \
                         'as themselves).',
            properties: { claimed_by_user_id: { type: :string } }
          }
        }
      }

      response '200', 'claimed — includes the revealed `key_value`' do
        # GameKey, with the otherwise-omitted `key_value` secret populated (the
        # claim response is the only place the secret is returned).
        schema type: :object, properties: {
          data: { '$ref' => '#/components/schemas/GameKey' },
          meta: { '$ref' => '#/components/schemas/GameKeyClaimMeta' }
        }
      end

      response '403', 'forbidden: caller lacks the Members role' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '409', 'already claimed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'no claimant resolved (service token omitted `claimed_by_user_id`)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/users/{user_id}/game_keys' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord user id of the donor.'

    get 'List a user\'s donated game keys' do
      tags 'Game Keys'
      description 'The keys donated by the user (claimed and unclaimed), newest ' \
                  'first, each embedding its `game` (null when unlinked). The ' \
                  'secret `key_value` is never included.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'donated game keys' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/GameKey' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/users/{user_id}/claimed_game_keys' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord user id of the claimer.'

    get 'List a user\'s claimed game keys' do
      tags 'Game Keys'
      description 'The keys the user claimed, newest claim first (`claimed_at` desc, then ' \
                  '`key_id` desc), each embedding its `game` (null when unlinked), so a ' \
                  'claimer can find their keys again. Readable by the claimer, Admins and ' \
                  'above, and the service token. The secret `key_value` is included only ' \
                  'when the caller is the claimer; it is omitted for staff and the service.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'claimed game keys' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/GameKey' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not the claimer, an Admin, a Superadmin, or the service token' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'unknown user' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
