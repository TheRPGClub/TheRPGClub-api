# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/game_images', type: :request do
  path '/api/v1/games/{game_id}/images' do
    parameter name: :game_id, in: :path, schema: { type: :string }, required: true, description: 'GamedbGame id.'

    get 'List images for a game' do
      tags 'Game Images'
      description 'Returns images attached to the game, primary entries first.'
      produces 'application/json'

      response '200', 'images list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/GameImage' } }
        }
      end

      response '404', 'game not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Upload a game image' do
      tags 'Game Images'
      description 'Uploads an image to Backblaze B2 and links it to the game. Restricted to admins or the service account. ' \
                  'Send as `multipart/form-data` with the `image` parameter.'
      consumes 'multipart/form-data'
      produces 'application/json'

      parameter name: :image, in: :formData, required: true, schema: {
        type: :object,
        properties: {
          file:       { type: :string, format: :binary, description: 'Binary image data.' },
          kind:       { type: :string, description: 'Image kind, e.g. `cover`, `screenshot`, `artwork`.' },
          is_primary: { type: :boolean, description: 'Whether this is the primary image for its kind. Defaults to true on create.' }
        },
        required: %w[file kind]
      }

      response '201', 'image created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GameImage' } }
      end

      response '403', 'forbidden — admin or service required' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'unprocessable (invalid image or missing config)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '502', 'Backblaze request failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/games/{game_id}/images/{id}' do
    parameter name: :game_id, in: :path, schema: { type: :string }, required: true
    parameter name: :id, in: :path, schema: { type: :string }, required: true, description: 'GamedbGameImage id.'

    patch 'Update a game image' do
      tags 'Game Images'
      description 'Updates image metadata (primary flag, position). Marking primary clears the flag on siblings of the same kind. Admin or service only.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              is_primary: { type: :boolean },
              position:   { type: :integer }
            }
          }
        },
        required: %w[data]
      }

      response '200', 'image updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GameImage' } }
      end

      response '403', 'forbidden — admin or service required' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'image not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'unprocessable entity' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    put 'Update a game image (alias)' do
      tags 'Game Images'
      description 'Equivalent to `PATCH` on the same path.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              is_primary: { type: :boolean },
              position:   { type: :integer }
            }
          }
        }
      }

      response '200', 'image updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GameImage' } }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Delete a game image' do
      tags 'Game Images'
      description 'Removes the image from Backblaze and the database. Admin or service only.'
      produces 'application/json'

      response '200', 'image deleted' do
        schema '$ref' => '#/components/schemas/DeletedResponse'
      end

      response '403', 'forbidden — admin or service required' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'image not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'Backblaze not configured' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '502', 'Backblaze request failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
