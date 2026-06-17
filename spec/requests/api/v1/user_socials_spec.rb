# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/user_socials', type: :request do
  # The client-writable UserSocial columns. NOTE the FK alias: the column is
  # `platform_id` (belongs_to :social_platform, foreign_key: :platform_id), NOT
  # `social_platform_id`; and the label column is `display_text`, NOT `handle`.
  # `user_id` is taken from the path.
  writable = {
    platform_id: { type: :integer, description: 'The social platform (social_platforms.id). Required on create.' },
    url: { type: :string, nullable: true, description: 'Profile URL. Optional; unique per (user, platform) when present (blank URLs skip the check).' },
    display_text: { type: :string, nullable: true, description: 'Optional free-form label; may repeat.' }
  }

  path '/api/v1/users/{user_id}/socials' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true

    get 'List a user\'s linked socials' do
      tags 'User Socials'
      description 'Open to any authenticated caller. Each row embeds its `social_platform`.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false
      parameter name: :limit, in: :query, schema: { type: :integer, maximum: 500 }, required: false,
        description: 'Deprecated alias for `per` (transitional, for the unaudited Discord bot).'
      parameter name: :offset, in: :query, schema: { type: :integer, minimum: 0 }, required: false,
        description: 'Deprecated; converted to a page number (transitional, for the unaudited Discord bot).'

      response '200', 'user socials' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/UserSocial' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Link a social account' do
      tags 'User Socials'
      description 'Owner-only. `platform_id` is required. `url` is optional but, when ' \
                  'present, must be unique per (user, platform) — duplicate accounts are ' \
                  'rejected with 422. `display_text` is an optional free-form label and may ' \
                  'repeat freely.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable, required: %w[platform_id] } },
        required: %w[data]
      }

      response '201', 'social link created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/UserSocial' } }
      end

      response '403', 'forbidden — caller is not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/user_socials/{id}' do
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'UserSocial id.'

    get 'Show a user social link' do
      tags 'User Socials'
      produces 'application/json'

      response '200', 'user social detail' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/UserSocial' } }
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Update a user social link' do
      tags 'User Socials'
      description 'Owner-only. Partial update. `url` (optional) stays unique per (user, platform); ' \
                  '`display_text` is an optional free-form label and may repeat.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } },
        required: %w[data]
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/UserSocial' } }
      end

      response '403', 'forbidden — caller is not the owner' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    put 'Replace a user social link (alias)' do
      tags 'User Socials'
      description 'Owner-only. Alias for PATCH (applied as a partial assign).'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: writable } }
      }

      response '200', 'updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/UserSocial' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a user social link' do
      tags 'User Socials'
      description 'Owner-only.'
      produces 'application/json'

      response '200', 'deleted' do
        schema '$ref' => '#/components/schemas/DeletedResponse'
      end

      response '403', 'forbidden — caller is not the owner' do
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
end
