# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/codex/entries/{entry_id}/images', type: :request do
  image = {
    type: :object,
    properties: {
      id: { type: :integer },
      url: { type: :string, description: 'Where the file is served from (Backblaze public URL).' },
      position: { type: :integer, minimum: 1, maximum: CodexEntryImage::MAX_PER_ENTRY,
                  description: 'Its place in the gallery, in upload order.' }
    },
    required: %w[id url position]
  }
  who = 'Whoever can edit the entry: for a Lore Entry its author or a Moderator and above (403 "Only its author ' \
        'or a Moderator can edit this."), for a History Event an Admin or Superadmin (403 "Only Admins can change ' \
        'Club History.").'
  gate = 'Belongs to the Club Codex Feature: not found for non-staff in Preview and for everyone when Off; the ' \
         'service token is not gated, but the bot gets 403 `feature_unavailable` when the Flag hides the Feature ' \
         'from the member it acts for.'
  storage = 'Files are kept in the Backblaze bucket the GameDB game images use: 422 `backblaze_not_configured` ' \
            'when it is not set up, 502 `backblaze_request_failed` when Backblaze refuses (nothing is changed).'

  path '/api/v1/codex/entries/{entry_id}/images' do
    parameter name: :entry_id, in: :path, schema: { type: :integer }, required: true,
      description: 'A History Event or Lore Entry id (any part; a Fun Fact refuses images).'

    post 'Add an image to an entry' do
      tags 'Club Codex'
      description "#{who} Adds the image at the end of the entry's gallery, up to " \
                  "#{CodexEntryImage::MAX_PER_ENTRY} per History Event or Lore Entry; Fun Facts take none. The " \
                  'response gives its `id` and `url`, so the website can also place it in the entry\'s Plate ' \
                  'story. Refusals carry `{ error, message }`, `message` written for members. Send ' \
                  "`multipart/form-data`; the bot adds `data[acting_user_id]`. #{storage} #{gate}"
      consumes 'multipart/form-data'
      produces 'application/json'
      parameter name: :data, in: :formData, required: true, schema: {
        type: :object,
        properties: {
          'data[file]' => { type: :string, format: :binary, description: 'JPEG, PNG, WebP or GIF, at most 10 MB.' },
          'data[acting_user_id]' => { type: :string,
                                      description: 'Service only, required: the member the bot acts for.' }
        },
        required: [ 'data[file]' ]
      }

      response '201', 'added' do
        schema type: :object, properties: { data: image }, required: %w[data]
      end

      response '400', 'the bot named no `data[acting_user_id]`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'not signed in' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'cannot edit the entry, or (bot) `feature_unavailable`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no such entry, or the Feature is hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', '`too_many_images` (the gallery is full), `images_not_allowed` (a Fun Fact), ' \
                      '`invalid_image` (no file, not an image, empty or too large) or `backblaze_not_configured`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '502', '`backblaze_request_failed`: nothing was added' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/codex/entries/{entry_id}/images/{id}' do
    parameter name: :entry_id, in: :path, schema: { type: :integer }, required: true
    parameter name: :id, in: :path, schema: { type: :integer }, required: true, description: 'The image id.'

    delete 'Remove an image from an entry' do
      tags 'Club Codex'
      description "#{who} Removes the file from storage, then the image; the images after it move up one " \
                  "place. The bot sends `acting_user_id` as a query parameter. #{storage} #{gate}"
      produces 'application/json'
      parameter name: :acting_user_id, in: :query, required: false, schema: { type: :string }

      response '200', 'removed' do
        schema type: :object, properties: {
          data: { type: :object, properties: { id: { type: :integer }, deleted: { type: :boolean } },
                  required: %w[id deleted] }
        }
      end

      response '400', 'the bot named no `acting_user_id`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'not signed in' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'cannot edit the entry, or (bot) `feature_unavailable`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'no such entry, no such image on it, or the Feature is hidden from the caller' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', '`backblaze_not_configured`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '502', '`backblaze_request_failed`: the image is kept, so the removal can be retried' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
