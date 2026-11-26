# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/patch_mark', type: :request do
  gate = 'Belongs to the Patch Notes Feature: a member who cannot use it (Preview: Admins and Superadmins only; ' \
         'Off: nobody) gets 404 `not_found`.'

  path '/api/v1/users/{user_id}/patch_mark' do
    parameter name: :user_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord user id of the member. Must be the signed-in member.'

    get 'Show a member\'s Patch Mark' do
      tags 'Patch Notes'
      description 'The Patch Mark: the number of the newest Patch the member has seen, the same on every ' \
                  'device. The website marks published Patches above it "NEW". `patch_mark` is null until the ' \
                  'website first sets it; `unseen` says whether a published Patch is newer. Only the member ' \
                  'themself may read it; another member, staff and the bot\'s service token get 403. ' \
                  "#{gate}"
      produces 'application/json'

      response '200', 'Patch Mark' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/PatchMark' } },
          required: %w[data]
      end

      response '403', 'forbidden: caller is not the member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the member cannot use the Patch Notes Feature' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    put 'Move a member\'s Patch Mark forward' do
      tags 'Patch Notes'
      description 'Moves the Patch Mark forward to a Patch number: the newest Patch /patch-notes or a Patch ' \
                  'page showed. It never moves backwards: a number below the stored mark keeps the stored one ' \
                  'and still returns 200 with it. A number past the newest published Patch is clamped to ' \
                  'that Patch; with no published Patch the mark stays as it is. Returns the stored Patch Mark. ' \
                  'Only the member themself may set it. ' \
                  "#{gate}"
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              patch_mark: { type: :integer, minimum: 1, example: 12,
                            description: 'The Patch number to move the Patch Mark forward to.' }
            },
            required: %w[patch_mark]
          }
        },
        required: %w[data]
      }

      response '200', 'the stored Patch Mark' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/PatchMark' } },
          required: %w[data]
      end

      response '422', '`patch_mark` missing or not a positive whole number' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '400', 'missing `data` parameter' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not the member' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'the member cannot use the Patch Notes Feature' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
