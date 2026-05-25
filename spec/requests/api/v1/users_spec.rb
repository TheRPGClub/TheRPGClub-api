# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/users', type: :request do
  path '/api/v1/users' do
    get 'List users' do
      tags 'Users'
      description 'Returns RPG Club users. The `q` parameter searches `username`, `global_name`, or an exact `user_id` match.'
      produces 'application/json'
      parameter name: :q, in: :query, schema: { type: :string }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :offset, in: :query, schema: { type: :integer, default: 0 }, required: false
      parameter name: :page, in: :query, schema: { type: :integer, default: 1 }, required: false

      response '200', 'users list' do
        schema type: :object, properties: {
          data: { type: :array, items: { type: :object, additionalProperties: true } },
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
      description 'Aggregated profile: user record + membership, socials, and preview lists/counts for now-playing, favorites, reviews, and completions.'
      produces 'application/json'
      parameter name: :preview_limit, in: :query, schema: { type: :integer, default: 10, maximum: 50 }, required: false,
        description: 'Per-preview-list size cap (now_playing, favorites, reviews, completions).'

      response '200', 'user detail' do
        schema type: :object, properties: {
          data: {
            type: :object,
            additionalProperties: true,
            properties: {
              membership: { type: :object, nullable: true, additionalProperties: true },
              socials:    { type: :array, items: { type: :object, additionalProperties: true } },
              now_playing: { type: :array, items: { type: :object, additionalProperties: true } },
              favorites:   { type: :array, items: { type: :object, additionalProperties: true } },
              reviews:     { type: :array, items: { type: :object, additionalProperties: true } },
              completions: { type: :array, items: { type: :object, additionalProperties: true } },
              counts: {
                type: :object,
                properties: {
                  now_playing: { type: :integer },
                  favorites:   { type: :integer },
                  reviews:     { type: :integer },
                  completions: { type: :integer },
                  backlog:     { type: :integer },
                  collections: { type: :integer }
                }
              }
            }
          }
        }
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
