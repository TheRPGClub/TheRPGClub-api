# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/memberscan', type: :request do
  path '/api/v1/memberscan' do
    post 'Start a memberscan' do
      tags 'Bot Jobs'
      description 'Superadmin only (the service token passes too). Queues a `memberscan` bot job, as the ' \
                  'bot\'s `/superadmin memberscan`: the bot fetches every server member, updates them and ' \
                  'marks the rest departed, then reports its counts as the job\'s `result_text`. The job ' \
                  'has a 30 minute claim lease. Payload: `{}`. Returns the queued job; poll ' \
                  '`GET /bot_jobs/{id}`.'
      produces 'application/json'

      response '202', 'memberscan job queued' do
        schema type: :object, properties: { data: { '$ref' => '#/components/schemas/BotJob' } }, required: %w[data]
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
