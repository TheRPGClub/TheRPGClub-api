# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/guild_channels', type: :request do
  channel_fields = {
    name: { type: :string, description: 'Channel name. Required.' },
    channel_type: { type: :integer, description: 'Discord ChannelType number (0 text, 2 voice, 4 category, ' \
                                                 '5 announcement, 15 forum). Required.' },
    parent_id: { type: :string, nullable: true, description: 'Parent category channel id, or null.' },
    position: { type: :integer, description: 'Position within the category (defaults to 0).' }
  }

  path '/api/v1/guild_channels' do
    get 'List the guild text channels' do
      tags 'Guild Channels'
      description 'Any authenticated caller. Text and announcement channels (types 0 and 5) as the bot ' \
                  'last reported them, for channel pickers. Ordered as Discord shows them: uncategorized ' \
                  'first, then by category position, then channel position. Each carries its ' \
                  '`category_name`. Not paginated; `meta.count` is the row count.'
      produces 'application/json'

      response '200', 'text channel list' do
        schema type: :object, properties: {
          data: { type: :array, items: { '$ref' => '#/components/schemas/GuildChannel' } },
          meta: { type: :object, properties: { count: { type: :integer } }, required: %w[count] }
        }
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/guild_channels/sync' do
    post 'Replace the guild channel list' do
      tags 'Guild Channels'
      description 'Service-only. The bot\'s full snapshot at startup: every channel in `data` is upserted ' \
                  'and every stored channel not in it is removed, in one transaction. Send categories ' \
                  '(type 4) too so text channels get their `category_name`. One invalid entry rejects ' \
                  'the whole sync (422) and leaves the old list in place.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: {
          data: {
            type: :array,
            items: {
              type: :object,
              properties: { channel_id: { type: :string, description: 'Discord channel snowflake. Required.' } }
                .merge(channel_fields),
              required: %w[channel_id name channel_type]
            }
          }
        },
        required: %w[data]
      }

      response '200', 'list replaced' do
        schema type: :object, properties: {
          data: {
            type: :object,
            properties: {
              synced: { type: :integer, description: 'Channels upserted.' },
              removed: { type: :integer, description: 'Stored channels removed because the snapshot lacked them.' }
            },
            required: %w[synced removed]
          }
        }
      end

      response '400', 'missing `data` array' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'an entry failed validation' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden - caller is not the service principal' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end

  path '/api/v1/guild_channels/{channel_id}' do
    parameter name: :channel_id, in: :path, schema: { type: :string }, required: true,
      description: 'Discord channel snowflake.'

    put 'Upsert one guild channel' do
      tags 'Guild Channels'
      description 'Service-only. The bot\'s channel create and update (rename, move): inserts the channel ' \
                  '(201) or refreshes it (200). The path id wins over any `channel_id` in the body.'
      consumes 'application/json'
      produces 'application/json'

      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        properties: { data: { type: :object, properties: channel_fields, required: %w[name channel_type] } },
        required: %w[data]
      }

      response '201', 'channel created' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GuildChannel' } }
      end

      response '200', 'channel updated' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/GuildChannel' } }
      end

      response '400', 'missing `data`' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '422', 'validation failed' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '403', 'forbidden - caller is not the service principal' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end

    delete 'Remove one guild channel' do
      tags 'Guild Channels'
      description 'Service-only. The bot\'s channel delete. Idempotent: 204 whether or not the channel ' \
                  'was stored.'

      response '204', 'channel removed (or was never stored)' do
      end

      response '403', 'forbidden - caller is not the service principal' do
        schema '$ref' => '#/components/schemas/Error'
      end

      response '401', 'unauthenticated' do
        schema '$ref' => '#/components/schemas/Error'
      end
    end
  end
end
