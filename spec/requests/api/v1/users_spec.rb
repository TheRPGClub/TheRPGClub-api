# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/users', type: :request do
  path '/api/v1/users' do
    get 'List users' do
      tags 'Users'
      description 'Returns RPG Club users. The `q` parameter searches `username`, `global_name`, or an ' \
                  'exact `user_id` match. `discord_id` and `has_platform` are exact/association filters ' \
                  'that stack with `q`. When `has_platform` is given, each user record additionally ' \
                  'carries its embedded `socials` list (the `UserWithSocials` shape).'
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
