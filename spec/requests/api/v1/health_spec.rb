# frozen_string_literal: true

require 'swagger_helper'

RSpec.describe 'api/v1/health', type: :request do
  path '/api/v1/health' do
    get 'Health check' do
      tags 'Health'
      description 'Verifies the API is up and the database connection is alive. Does not require authentication.'
      produces 'application/json'
      security []

      response '200', 'service is healthy' do
        schema type: :object, properties: {
          ok: { type: :boolean, example: true }
        }, required: %w[ok]
      end
    end
  end
end
