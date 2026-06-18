# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/users', type: :request do
  path '/api/v1/users' do
    get 'List users' do
      tags 'Users'
      description 'Returns RPG Club users. The `q` parameter searches `username`, `global_name`, or an ' \
                  'exact `user_id` match. `discord_id`, `has_platform` and `has_emoji_name` are ' \
                  'exact/association filters that stack with `q`. When `has_platform` is given, each ' \
                  'user record additionally carries its embedded `socials` list (the `UserWithSocials` ' \
                  'shape); when `has_emoji_name` is given (and `has_platform` is not), records use the ' \
                  '`UserService` shape so the bot sees each user\'s `emoji_name`.'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: false
      parameter name: :discord_id, in: :query, schema: { type: :string }, required: false,
        description: 'Filter by exact Discord snowflake (the `user_id`). Accepts a comma-separated list.'
      parameter name: :has_platform, in: :query, schema: { type: :string }, required: false,
        description: 'Filter to users with at least one social link on the given platform(s): a ' \
                     'comma-separated list of platform tokens matched case-insensitively against ' \
                     '`social_platforms.label`. Canonical tokens `steam`, `psn`, `xbl`, `nsw`, ' \
                     '`completionator` map to the bot\'s label aliases (e.g. `xbl` → "Xbox", `nsw` → ' \
                     '"Nintendo"/"Switch"); any other token matches the label literally. Matched users ' \
                     'include their embedded `socials`.'
      parameter name: :has_emoji_name, in: :query, schema: { type: :boolean }, required: false,
        description: 'When truthy, returns only users whose `emoji_name` is set. Matched users use the ' \
                     '`UserService` shape (which includes `emoji_name`). Used by UserEmojiService to ' \
                     'sync emoji display names. Takes effect only when `has_platform` is not also given.'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'users list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/UserWithSocials' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/users/{user_id}' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubUser id (Discord user id).'

    get 'Show user profile' do
      tags 'Users'
      description 'Aggregated profile: user record + membership, socials, and preview lists/counts for now-playing, favorites, reviews, completions, and journal (recently journaled games).'
      produces 'application/json'
      parameter name: :preview_limit, in: :query, schema: { type: :integer, default: 10, maximum: 50 }, required: false,
        description: 'Per-preview-list size cap (now_playing, favorites, reviews, completions, journal).'

      response '200', 'user detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/User' } }
      end

      response '404', 'user not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update service-managed user fields' do
      tags 'Users'
      description 'Service-only. Updates the Discord-sync fields the bot owns. `last_seen` maps to ' \
                  '`last_seen_at`; `departed` (boolean) toggles `server_left_at` — `true` stamps a ' \
                  'departure (preserving an existing one), `false` clears it (a rejoin). `emoji_name` ' \
                  'may be set or cleared (null). Only the supplied keys are changed.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              emoji_name: { type: :string, nullable: true, description: 'The user\'s generated Discord emoji name, or null to clear it.' },
              last_seen: { type: :string, format: 'date-time', description: 'When the user was last seen active; stored as `last_seen_at`.' },
              departed: { type: :boolean, description: 'true marks the user departed (sets `server_left_at`); false clears it (rejoin).' }
            }
          }
        },
        required: %w[data]
      }

      response '200', 'user updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/UserService' } }
      end

      response '403', 'forbidden — caller is not the service principal' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'user not found' do
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

  path '/api/v1/users/upsert' do
    post 'Upsert a user by Discord id' do
      tags 'Users'
      description 'Service-only. Creates or updates a user keyed by `discord_id` (the Discord ' \
                  'snowflake / `user_id`). Called on guild member join/update events and by the ' \
                  '`memberscan` admin command. Passing `server_left_at: null` clears a prior departure ' \
                  '(a rejoin). Returns 201 when a new user was created, 200 when an existing one was ' \
                  'updated.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              discord_id: { type: :string, description: 'The Discord snowflake. Required; becomes the `user_id`.' },
              username: { type: :string, nullable: true },
              global_name: { type: :string, nullable: true },
              is_bot: { type: :boolean, description: 'Defaults to false on create.' },
              server_joined_at: { type: :string, format: 'date-time', nullable: true },
              server_left_at: { type: :string, format: 'date-time', nullable: true, description: 'Set to null to clear a departure (rejoin).' }
            },
            required: %w[discord_id]
          }
        },
        required: %w[data]
      }

      response '201', 'user created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/UserService' } }
      end

      response '200', 'user updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/UserService' } }
      end

      response '422', 'missing `discord_id`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden — caller is not the service principal' do
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

  path '/api/v1/users/mark_departed' do
    post 'Bulk-mark departed users' do
      tags 'Users'
      description 'Service-only. Marks every currently active user (those with `server_left_at` unset) ' \
                  'whose id is NOT in `active_ids` as departed (stamps `server_left_at`). Already-' \
                  'departed users are left untouched. Mirrors the bot\'s `memberscan` reconciliation. ' \
                  'An empty `active_ids` list is rejected. Returns the count of users newly marked.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          active_ids: {
            type: :array, items: { type: :string },
            description: 'The Discord ids of members still present in the guild.'
          }
        },
        required: %w[active_ids]
      }

      response '200', 'users marked departed' do
        schema '$ref' => '#/components/schemas/MarkDepartedResult'
      end

      response '422', 'empty `active_ids` list' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden — caller is not the service principal' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/users/{user_id}/avatar_history' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true, description: 'RpgClubUser id (Discord user id).'

    get 'List a user\'s avatar history' do
      tags 'Users'
      description 'Returns the user\'s avatar-change log, newest first. Open to any authenticated caller.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'avatar history list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/UserAvatarHistory' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Record an avatar change' do
      tags 'Users'
      description 'Service-only. Inserts a new avatar-history row. `changed_at` is DB-stamped.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              avatar_hash: { type: :string, nullable: true, description: 'The Discord avatar hash.' },
              avatar_url: { type: :string, nullable: true, description: 'The CDN/stored avatar URL.' }
            }
          }
        },
        required: %w[data]
      }

      response '201', 'avatar history record created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/UserAvatarHistory' } }
      end

      response '403', 'forbidden — caller is not the service principal' do
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

  path '/api/v1/users/avatar_history_counts' do
    get 'Avatar-history counts per member' do
      tags 'Users'
      description 'Aggregate avatar-change count for every active, non-bot member (`server_left_at` ' \
                  'is null and `is_bot` is false) who has at least one logged avatar change, ordered ' \
                  'by display name (`global_name`, then `username`, then `user_id`; ties broken by ' \
                  '`user_id`). Open to any authenticated caller. Backs the bot\'s avatar-history ' \
                  'leaderboard (`getAllMembersAvatarHistoryCounts`).'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'avatar-history counts' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/AvatarHistoryCount' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/users/{user_id}/avatar' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'Stream user avatar' do
      tags 'Users'
      description 'Returns the cached PNG avatar blob for the user. Public — does not require authentication.'
      produces 'image/png', 'application/json'
      security []

      response '200', 'avatar PNG' do
        header 'Content-Type', schema: { type: :string }, description: 'image/png'
      end

      response '404', 'avatar not stored' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/users/{user_id}/profile-image' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'Stream user profile image' do
      tags 'Users'
      description 'Returns the user-uploaded profile banner image. Public — does not require authentication.'
      produces 'image/png', 'application/json'
      security []

      response '200', 'profile image PNG' do
        header 'Content-Type', schema: { type: :string }, description: 'image/png'
      end

      response '404', 'profile image not stored' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
