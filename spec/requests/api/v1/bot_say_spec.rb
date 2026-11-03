# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/bot_say', type: :request do
  path '/api/v1/bot_say' do
    post 'Make the bot say a message' do
      tags 'Bot Jobs'
      description 'Superadmin only (the service token passes too). Queues a `say` bot job, as the ' \
                  'bot\'s `/superadmin say`: the bot posts `content` in `channel_id`, or, with ' \
                  '`reply_to_message_link`, replies to that message. The channel must be a synced text ' \
                  'channel (`GET /guild_channels`), and a linked message must be in that channel (and in ' \
                  'the club\'s server). The job allows plain user mentions only, never @everyone, @here or ' \
                  'roles (payload: `SayJobPayload`). Returns the queued job; poll `GET /bot_jobs/{id}`.'
      consumes 'application/json'
      produces 'application/json'
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :object,
            properties: {
              channel_id: { type: :string, description: 'A synced text channel id.' },
              content: { type: :string, maxLength: BotSay::CONTENT_MAX,
                         description: 'Trimmed; line breaks are kept.' },
              reply_to_message_link: {
                type: :string, nullable: true,
                description: 'Optional Discord message link (https://discord.com/channels/{guild}/{channel}/' \
                             '{message}) to reply to. Blank means no reply.'
              }
            },
            required: %w[channel_id content]
          }
        },
        required: %w[data]
      }

      response '202', 'say job queued' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/BotJob' } }, required: %w[data]
      end

      response '422', 'not a synced text channel, blank or too long content, or a bad message link' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden: caller is not a Superadmin or the service token' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
