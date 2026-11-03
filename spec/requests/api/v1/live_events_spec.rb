# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/live_events', type: :request do
  event_response = {
    type: :object, properties: { data: { '$ref' => '#/components/schemas/LiveEvent' } }, required: %w[data]
  }

  path '/api/v1/live_events' do
    get 'List live events' do
      tags 'Live Events'
      description 'Moderators and up, and the service. Newest first, with the Discord thread and event ids ' \
                  'once the bot has made them.'
      produces 'application/json'
      parameter name: :page, in: :query, schema: { type: :integer, default: 1, minimum: 1 }, required: false
      parameter name: :per, in: :query, schema: { type: :integer, default: 50, maximum: 500 }, required: false

      response '200', 'live events' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/LiveEvent' } },
          meta: { '$ref' => '#/components/schemas/PaginationMeta' }
        }, required: %w[data meta]
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not a Moderator and up or the service token' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    post 'Create a live event' do
      tags 'Live Events'
      description 'Moderators and up, and the service. Saves the event as `queued` and queues the ' \
                  '`live_event_create` bot job (payload `{ live_event_id }`), which makes the forum thread ' \
                  'and the Discord scheduled event, as the bot\'s `/live-stream create` did. The topic is ' \
                  'squished, at most 100 characters; `starts_at` must be in the future and `ends_at` after ' \
                  'it (send UTC or offset instants). The image is optional: send `image_url` (http or https) ' \
                  'as JSON, or send `multipart/form-data` with the same `data[...]` fields and the file as ' \
                  '`data[image]` (JPEG, PNG, WebP or GIF, at most 10 MB), which is stored in Backblaze and ' \
                  'saved as its public URL. Sending both is refused with 422.'
      consumes 'application/json', 'multipart/form-data'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              topic: { type: :string, maxLength: LiveEvent::TOPIC_MAX },
              starts_at: { type: :string, format: 'date-time' },
              ends_at: { type: :string, format: 'date-time' },
              image_url: { type: :string, nullable: true, maxLength: LiveEvent::IMAGE_URL_MAX },
              image: { type: :string, format: :binary, description: 'multipart only: the image file.' }
            },
            required: %w[topic starts_at ends_at]
          }
        },
        required: %w[data]
      }

      response '201', 'live event saved and bot job queued' do
        schema event_response
      end

      response '422', 'invalid topic, times, image URL or image file; both an image URL and a file; ' \
                      'or Backblaze not configured (`backblaze_not_configured`)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '502', 'the Backblaze upload failed (`backblaze_request_failed`)' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not a Moderator and up or the service token' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/live_events/{id}' do
    parameter name: :id, in: :path, schema: { type: :integer }, required: true, description: 'LiveEvent id.'

    get 'Get a live event' do
      tags 'Live Events'
      description 'Moderators and up, and the service.'
      produces 'application/json'

      response '200', 'the live event' do
        schema event_response
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not a Moderator and up or the service token' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    patch 'Record a live event\'s Discord thread, event and status' do
      tags 'Live Events'
      description 'Service only (the bot). Records each step of `live_event_create` as it is done: the ' \
                  'thread id with status `thread_created`, then the event id with `created`, or `failed`. ' \
                  'A retried job reads the event first and skips the steps whose id is already set. ' \
                  'Other fields are ignored.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              discord_thread_id: { type: :string, pattern: '^\d{1,30}$' },
              discord_event_id: { type: :string, pattern: '^\d{1,30}$' },
              status: { type: :string, enum: LiveEvent::STATUSES }
            }
          }
        },
        required: %w[data]
      }

      response '200', 'the updated live event' do
        schema event_response
      end

      response '422', 'unknown status or an id that is not a Discord snowflake' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '404', 'not found' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not the service token' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
